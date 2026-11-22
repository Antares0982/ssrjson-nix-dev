"""Check CI scripts without network access."""

import json
import os
import subprocess
import tempfile
from pathlib import Path


def main():
    scripts = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        repo = root / "repo"
        remote = root / "origin.git"
        bin_dir = root / "bin"
        repo.mkdir()
        bin_dir.mkdir()
        output = root / "output"
        nix_log = root / "nix.log"
        env = os.environ | {
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "CI Test",
            "GIT_AUTHOR_EMAIL": "ci@example.invalid",
            "GIT_COMMITTER_NAME": "CI Test",
            "GIT_COMMITTER_EMAIL": "ci@example.invalid",
            "GITHUB_OUTPUT": str(output),
            "GITHUB_REF_TYPE": "branch",
            "GITHUB_REF_NAME": "dev",
            "GITHUB_RUN_ATTEMPT": "1",
            "NIX_LOG": str(nix_log),
        }

        def run(*args, success=True, **variables):
            result = subprocess.run(
                args,
                check=False,
                cwd=repo,
                env=env | variables,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            assert (result.returncode == 0) == success, result.stdout
            return result.stdout.strip()

        def refs():
            return run("git", "ls-remote", "--heads", "origin")

        def read_outputs():
            return dict(line.split("=", 1) for line in output.read_text().splitlines())

        def prepare(number, **variables):
            run("git", "checkout", "--detach", base)
            run("git", "--git-dir", str(remote), "update-ref", "refs/heads/dev", base)
            output.write_text("")
            env.update(
                GITHUB_RUN_ID=str(number),
                FAKE_REV=f"{number:040x}"[::-1],
                DO_UPDATE="false",
                NEW_BRANCH="true",
                FAKE_UPDATE="change",
            )
            run("bash", str(scripts / "flake-update.sh"), "prepare", **variables)
            return read_outputs()

        def finalize(values, success=True, **variables):
            return run(
                "bash",
                str(scripts / "flake-update.sh"),
                "finalize",
                success=success,
                **(
                    {
                        "PENDING_BRANCH": values["branch_name"],
                        "FINAL_BRANCH": values["final_branch_name"],
                        "UPDATE_SHA": values["update_sha"],
                        "PREPARE_RESULT": "success",
                        "X86_RESULT": "success",
                        "ARM_RESULT": "success",
                        "MAC_RESULT": "success",
                    }
                    | variables
                ),
            )

        mock = bin_dir / "nix"
        mock.write_text("""#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "$NIX_LOG"
if [[ "$1" == build ]]; then
    [[ "$2" != "${FAIL_TARGET:-}" ]]
    exit
fi
case "$FAKE_UPDATE" in
    fail) exit 1 ;;
    none) exit 0 ;;
esac
printf '{"nodes":{"nixpkgs":{"locked":{"rev":"%s"}}}}\\n' "$FAKE_REV" > flake.lock
git add flake.lock
git commit -qm "Update lockfile"
""")
        mock.chmod(0o755)
        run("git", "init", "--bare", str(remote))
        run("git", "init", "-b", "dev")
        run("git", "remote", "add", "origin", str(remote))
        (repo / "flake.lock").write_text("{}\n")
        run("git", "add", ".")
        run("git", "commit", "-m", "Baseline")
        base = run("git", "rev-parse", "HEAD")
        run("git", "push", "origin", "dev")

        for number, mode in enumerate(("new", "direct"), 1):
            for offset, status in enumerate(
                ("success", "failure", "cancelled", "skipped")
            ):
                values = prepare(
                    number * 10 + offset,
                    DO_UPDATE="true",
                    NEW_BRANCH=str(mode == "new").lower(),
                )
                assert values["branch_name"] in refs()
                assert run("git", "--git-dir", str(remote), "rev-parse", "dev") == base
                passed = status == "success"
                finalize(
                    values,
                    success=passed,
                    NEW_BRANCH=str(mode == "new").lower(),
                    ARM_RESULT=status,
                )
                remaining = refs()
                assert values["branch_name"] not in remaining
                if passed:
                    assert (
                        f"{values['update_sha']}\trefs/heads/{values['final_branch_name']}"
                        in remaining
                    )
                else:
                    assert values["update_sha"] not in remaining

        for number, variables in enumerate(
            (
                {"FAKE_UPDATE": "none"},
                {"NEW_BRANCH": "false", "DO_UPDATE": "false"},
                {"FAKE_UPDATE": "fail", "success": False},
                {
                    "NEW_BRANCH": "false",
                    "DO_UPDATE": "true",
                    "GITHUB_REF_TYPE": "tag",
                    "success": False,
                },
            ),
            30,
        ):
            values = prepare(number, **variables)
            assert values == {"update_sha": base}
            assert "pending-flake-update/" not in refs()

        values = prepare(40)
        run(
            "git",
            "--git-dir",
            str(remote),
            "update-ref",
            f"refs/heads/{values['final_branch_name']}",
            base,
        )
        finalize(values)
        assert (
            run(
                "git",
                "--git-dir",
                str(remote),
                "rev-parse",
                values["final_branch_name"],
            )
            == base
        )
        assert values["branch_name"] not in refs()

        values = prepare(41, NEW_BRANCH="false", DO_UPDATE="true")
        run("git", "checkout", "--detach", base)
        run("git", "commit", "--allow-empty", "-m", "Concurrent change")
        concurrent = run("git", "rev-parse", "HEAD")
        run("git", "push", "origin", "HEAD:refs/heads/dev")
        finalize(values, success=False, NEW_BRANCH="false")
        assert run("git", "--git-dir", str(remote), "rev-parse", "dev") == concurrent
        assert values["branch_name"] not in refs()

        values = prepare(42)
        hook = remote / "hooks/pre-receive"
        hook.write_text("""#!/usr/bin/env bash
while read -r old new ref; do
    if [[ "$new" == 0000000000000000000000000000000000000000 ]]; then exit 1; fi
done
""")
        hook.chmod(0o755)
        finalize(values, success=False)
        assert values["branch_name"] in refs()
        hook.unlink()
        run("git", "push", "origin", "--delete", values["branch_name"])

        (repo / "ci").mkdir()
        config = repo / "ci/pyver.json"
        config.write_text(
            json.dumps(
                {
                    "minSupportVer": 11,
                    "minSupportNoGILVer": 14,
                    "latestWheelBuildableVer": 15,
                }
            )
        )
        nix_log.write_text("")
        run("bash", str(scripts / "ssrjson-test.sh"), str(repo), base)
        calls = nix_log.read_text().splitlines()
        assert [line.split()[1].split("#")[1] for line in calls] == [
            f"ssrjson-wheel-py3{version}"
            for version in ("15t", "14t", "15", "14", "13", "12", "11")
        ]
        for line in calls:
            assert "--no-link" in line and "--no-write-lock-file" in line
            assert (
                f"--override-input ssrjson-nix-dev github:Antares0982/ssrjson-nix-dev/{base}"
                in line
            )
        nix_log.write_text("")
        run(
            "bash",
            str(scripts / "ssrjson-test.sh"),
            str(repo),
            base,
            success=False,
            FAIL_TARGET=f"{repo}#ssrjson-wheel-py315t",
        )
        assert len(nix_log.read_text().splitlines()) == 1
        print("CI checks passed: publication, cleanup, conflicts, and wheel targets")


if __name__ == "__main__":
    main()
