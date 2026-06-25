#!/usr/bin/env python3
import argparse
import configparser
from dataclasses import dataclass
import datetime as dt
import shlex
import sqlite3
import subprocess
import sys
from pathlib import Path
from typing import List, Optional

DEFAULT_REMOTE_DIR = "/sdcard/DCIM/Camera"
DEFAULT_LOCAL_DIR = Path("~/Pictures/m14u").expanduser()
DEFAULT_DB_NAME = "adb_photo_export.sqlite3"
SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_CFG_PATH = SCRIPT_DIR / "cfg" / "pull_camera.ini"
DEFAULT_DB_PATH = SCRIPT_DIR / "db" / DEFAULT_DB_NAME


@dataclass
class TransferOptions:
    dry_run: bool
    fast: bool
    retransfer_deleted: bool
    force: bool
    record_existing: bool


@dataclass
class TransferJob:
    name: str
    remote_dir: str
    local_dir: Path


@dataclass
class AppConfig:
    device_id: Optional[str]
    db_path: Path
    options: TransferOptions
    jobs: List[TransferJob]


def run(cmd, *, check=True, capture_output=True, text=True):
    return subprocess.run(
        cmd,
        check=check,
        capture_output=capture_output,
        text=text,
    )


def now_iso():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def adb_cmd(*args, device_id=None):
    cmd = ["adb"]

    if device_id:
        cmd.extend(["-s", device_id])

    cmd.extend(args)
    return cmd


def check_adb(device_id=None):
    try:
        run(["adb", "version"])
    except FileNotFoundError:
        print(
            "错误：找不到 adb。请先安装 Android platform-tools，并确保 adb 在 PATH 里。",
            file=sys.stderr,
        )
        sys.exit(1)

    result = run(["adb", "devices"])
    lines = result.stdout.strip().splitlines()[1:]
    devices = []

    for line in lines:
        parts = line.split()

        if len(parts) >= 2 and parts[1] == "device":
            devices.append(parts[0])

    if not devices:
        print("错误：没有检测到已授权的 Android 设备。", file=sys.stderr)
        print("请检查手机 USB 调试授权，然后执行：adb devices", file=sys.stderr)
        sys.exit(1)

    if device_id and device_id not in devices:
        print(f"错误：没有检测到配置的 Android 设备：{device_id}", file=sys.stderr)
        print("当前已授权设备：", file=sys.stderr)

        for device in devices:
            print(f"  {device}", file=sys.stderr)

        print("请检查 cfg 配置中的 [adb] device_id，或执行：adb devices", file=sys.stderr)
        sys.exit(1)


def adb_shell_text(command, device_id=None):
    result = run(adb_cmd("shell", command, device_id=device_id))
    return result.stdout.replace("\r\n", "\n").replace("\r", "\n")


def list_remote_files(remote_dir, device_id=None):
    quoted = shlex.quote(remote_dir)
    output = adb_shell_text(f"find {quoted} -type f", device_id=device_id)

    files = []
    for line in output.splitlines():
        line = line.strip()
        if line:
            files.append(line)

    return files


def get_remote_stat(remote_path, device_id=None):
    quoted = shlex.quote(remote_path)
    output = adb_shell_text(f"stat -c '%s %Y' {quoted}", device_id=device_id).strip()

    parts = output.split()
    if len(parts) < 2:
        raise RuntimeError(
            f"无法读取远端文件信息：{remote_path}; stat 输出：{output!r}"
        )

    return int(parts[0]), int(parts[1])


def basename_of(remote_path):
    return remote_path.rstrip("/").split("/")[-1]


def local_path_for(remote_path, remote_dir, local_dir):
    rel = remote_path.removeprefix(remote_dir).lstrip("/")
    return local_dir / rel


def connect_db(db_path):
    db_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path)

    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS transfers (
            remote_path TEXT NOT NULL,
            remote_size INTEGER NOT NULL,
            remote_mtime INTEGER NOT NULL,
            local_relpath TEXT NOT NULL,
            transferred_at TEXT NOT NULL,
            PRIMARY KEY (remote_path, remote_size, remote_mtime)
        )
        """
    )

    conn.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_transfers_remote_path
        ON transfers(remote_path)
        """
    )

    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS transferred_names (
            filename TEXT PRIMARY KEY,
            first_seen_remote_path TEXT NOT NULL,
            local_relpath TEXT NOT NULL,
            transferred_at TEXT NOT NULL
        )
        """
    )

    # 兼容旧版本数据库：
    # 把 transfers 里已有记录补进 transferred_names。
    # 不在 SQL 里取 basename，避免依赖 SQLite 非内置函数。
    rows = conn.execute(
        """
        SELECT remote_path, local_relpath, transferred_at
        FROM transfers
        WHERE local_relpath IS NOT NULL
        """
    ).fetchall()

    for remote_path, local_relpath, transferred_at in rows:
        filename = Path(local_relpath).name

        if not filename:
            continue

        conn.execute(
            """
            INSERT OR IGNORE INTO transferred_names (
                filename,
                first_seen_remote_path,
                local_relpath,
                transferred_at
            )
            VALUES (?, ?, ?, ?)
            """,
            (
                filename,
                remote_path,
                local_relpath,
                transferred_at,
            ),
        )

    conn.commit()
    return conn


def has_successful_transfer(conn, remote_path, remote_size, remote_mtime):
    row = conn.execute(
        """
        SELECT 1
        FROM transfers
        WHERE remote_path = ?
          AND remote_size = ?
          AND remote_mtime = ?
        LIMIT 1
        """,
        (remote_path, remote_size, remote_mtime),
    ).fetchone()

    return row is not None


def has_transferred_filename(conn, filename):
    row = conn.execute(
        """
        SELECT 1
        FROM transferred_names
        WHERE filename = ?
        LIMIT 1
        """,
        (filename,),
    ).fetchone()

    return row is not None


def record_filename(conn, filename, remote_path, local_relpath):
    conn.execute(
        """
        INSERT OR IGNORE INTO transferred_names (
            filename,
            first_seen_remote_path,
            local_relpath,
            transferred_at
        )
        VALUES (?, ?, ?, ?)
        """,
        (
            filename,
            remote_path,
            local_relpath,
            now_iso(),
        ),
    )


def record_success(conn, remote_path, remote_size, remote_mtime, local_relpath):
    filename = Path(local_relpath).name

    conn.execute(
        """
        INSERT OR REPLACE INTO transfers (
            remote_path,
            remote_size,
            remote_mtime,
            local_relpath,
            transferred_at
        )
        VALUES (?, ?, ?, ?, ?)
        """,
        (
            remote_path,
            remote_size,
            remote_mtime,
            local_relpath,
            now_iso(),
        ),
    )

    record_filename(conn, filename, remote_path, local_relpath)

    conn.commit()


def record_fast_success(conn, remote_path, local_relpath):
    filename = Path(local_relpath).name
    record_filename(conn, filename, remote_path, local_relpath)
    conn.commit()


def pull_file(remote_path, local_path, remote_size=None, device_id=None):
    local_path.parent.mkdir(parents=True, exist_ok=True)

    tmp_path = local_path.with_name(local_path.name + ".part")

    if tmp_path.exists():
        tmp_path.unlink()

    print(f"pull: {remote_path}")
    result = subprocess.run(
        adb_cmd("pull", remote_path, str(tmp_path), device_id=device_id)
    )

    if result.returncode != 0:
        print(f"失败：{remote_path}", file=sys.stderr)
        if tmp_path.exists():
            print(f"保留未完成文件：{tmp_path}", file=sys.stderr)
        return False

    if not tmp_path.exists():
        print(f"失败：adb pull 没有生成目标文件：{tmp_path}", file=sys.stderr)
        return False

    if remote_size is not None:
        local_size = tmp_path.stat().st_size
        if local_size != remote_size:
            print(
                f"失败：文件大小不一致：{remote_path}; "
                f"remote={remote_size}, local={local_size}",
                file=sys.stderr,
            )
            print(f"保留未完成文件：{tmp_path}", file=sys.stderr)
            return False

    tmp_path.replace(local_path)
    return True


def config_path_value(value, base_dir=SCRIPT_DIR):
    path = Path(value).expanduser()

    if path.is_absolute():
        return path

    return base_dir / path


def config_bool(parser, section, option, default):
    if parser.has_option(section, option):
        return parser.getboolean(section, option)

    return default


def option_value(cli_value, config_value):
    if cli_value is not None:
        return cli_value

    return config_value


def load_app_config(args):
    config_path = Path(args.config).expanduser() if args.config else DEFAULT_CFG_PATH
    parser = configparser.ConfigParser()

    if config_path.exists():
        parser.read(config_path)
    elif args.config:
        print(f"错误：找不到配置文件：{config_path}", file=sys.stderr)
        sys.exit(1)

    device_id = None

    if parser.has_option("adb", "device_id"):
        device_id = parser.get("adb", "device_id").strip() or None

    db_path = DEFAULT_DB_PATH

    if parser.has_option("defaults", "db"):
        db_path = config_path_value(parser.get("defaults", "db"))

    if args.db:
        db_path = Path(args.db).expanduser()

    config_options = TransferOptions(
        dry_run=config_bool(parser, "defaults", "dry_run", False),
        fast=config_bool(parser, "defaults", "fast", False),
        retransfer_deleted=config_bool(parser, "defaults", "retransfer_deleted", False),
        force=config_bool(parser, "defaults", "force", False),
        record_existing=config_bool(parser, "defaults", "record_existing", False),
    )

    options = TransferOptions(
        dry_run=option_value(args.dry_run, config_options.dry_run),
        fast=option_value(args.fast, config_options.fast),
        retransfer_deleted=option_value(
            args.retransfer_deleted,
            config_options.retransfer_deleted,
        ),
        force=option_value(args.force, config_options.force),
        record_existing=option_value(
            args.record_existing,
            config_options.record_existing,
        ),
    )

    jobs = []

    if args.remote or args.local:
        jobs.append(
            TransferJob(
                name="cli",
                remote_dir=(args.remote or DEFAULT_REMOTE_DIR).rstrip("/"),
                local_dir=Path(args.local or DEFAULT_LOCAL_DIR).expanduser(),
            )
        )
    else:
        for section in parser.sections():
            if not section.startswith("job."):
                continue

            enabled = parser.getboolean(section, "enabled", fallback=True)

            if not enabled:
                continue

            if not parser.has_option(section, "remote"):
                print(f"错误：配置节 [{section}] 缺少 remote。", file=sys.stderr)
                sys.exit(1)

            if not parser.has_option(section, "local"):
                print(f"错误：配置节 [{section}] 缺少 local。", file=sys.stderr)
                sys.exit(1)

            remote_dir = parser.get(section, "remote").strip().rstrip("/")
            local_dir = config_path_value(parser.get(section, "local"))

            if not remote_dir:
                print(f"错误：配置节 [{section}] remote 不能为空。", file=sys.stderr)
                sys.exit(1)

            jobs.append(
                TransferJob(
                    name=section.removeprefix("job."),
                    remote_dir=remote_dir,
                    local_dir=local_dir,
                )
            )

    if not jobs:
        jobs.append(
            TransferJob(
                name="default",
                remote_dir=DEFAULT_REMOTE_DIR,
                local_dir=DEFAULT_LOCAL_DIR,
            )
        )

    return AppConfig(
        device_id=device_id,
        db_path=db_path,
        options=options,
        jobs=jobs,
    )


def add_boolean_arg(parser, name, *, help):
    parser.add_argument(
        f"--{name}",
        dest=name.replace("-", "_"),
        action="store_true",
        default=None,
        help=help,
    )

    parser.add_argument(
        f"--no-{name}",
        dest=name.replace("-", "_"),
        action="store_false",
        help=argparse.SUPPRESS,
    )


def run_job(job, conn, options, device_id=None, job_number=1, job_count=1):
    remote_dir = job.remote_dir.rstrip("/")
    local_dir = job.local_dir.expanduser()

    local_dir.mkdir(parents=True, exist_ok=True)

    if job_count > 1:
        print(f"任务：{job.name} ({job_number}/{job_count})")

    print(f"来源：{remote_dir}")
    print(f"目标：{local_dir}")
    print(f"fast：{options.fast}")
    print()

    remote_files = list_remote_files(remote_dir, device_id=device_id)

    total = len(remote_files)
    pulled = 0
    skipped_logged = 0
    skipped_local = 0
    recorded_existing = 0
    failed = 0

    if total == 0:
        print("没有找到远端文件。")
        return {
            "total": total,
            "pulled": pulled,
            "skipped_logged": skipped_logged,
            "skipped_local": skipped_local,
            "recorded_existing": recorded_existing,
            "failed": failed,
        }

    for index, remote_path in enumerate(remote_files, start=1):
        filename = basename_of(remote_path)
        local_path = local_path_for(remote_path, remote_dir, local_dir)
        local_relpath = str(local_path.relative_to(local_dir))
        local_exists = local_path.exists()

        if options.fast:
            logged_by_name = has_transferred_filename(conn, filename)

            if not options.force:
                if logged_by_name:
                    if local_exists:
                        skipped_logged += 1
                        print(f"[{index}/{total}] skip fast-logged: {filename}")
                        continue

                    if not options.retransfer_deleted:
                        skipped_logged += 1
                        print(
                            f"[{index}/{total}] "
                            f"skip fast-deleted-but-logged: {filename}"
                        )
                        continue

                else:
                    if local_exists:
                        if options.record_existing:
                            if not options.dry_run:
                                record_fast_success(conn, remote_path, local_relpath)
                            recorded_existing += 1
                            print(f"[{index}/{total}] record fast-existing: {filename}")
                            continue

                        skipped_local += 1
                        print(f"[{index}/{total}] skip fast-local-exists: {filename}")
                        continue

            if options.dry_run:
                pulled += 1
                print(
                    f"[{index}/{total}] would pull fast: {remote_path} -> {local_path}"
                )
                continue

            ok = pull_file(remote_path, local_path, remote_size=None, device_id=device_id)

            if ok:
                record_fast_success(conn, remote_path, local_relpath)
                pulled += 1
            else:
                failed += 1

            continue

        # 非 fast：严格模式，按 remote_path + size + mtime 判断
        try:
            remote_size, remote_mtime = get_remote_stat(remote_path, device_id=device_id)
        except Exception as e:
            failed += 1
            print(f"[{index}/{total}] stat 失败：{remote_path}; {e}", file=sys.stderr)
            continue

        logged = has_successful_transfer(conn, remote_path, remote_size, remote_mtime)

        if not options.force:
            if logged:
                if local_exists:
                    skipped_logged += 1
                    print(f"[{index}/{total}] skip logged: {local_relpath}")
                    continue

                if not options.retransfer_deleted:
                    skipped_logged += 1
                    print(f"[{index}/{total}] skip deleted-but-logged: {local_relpath}")
                    continue

            else:
                if local_exists and local_path.stat().st_size == remote_size:
                    if options.record_existing:
                        if not options.dry_run:
                            record_success(
                                conn,
                                remote_path,
                                remote_size,
                                remote_mtime,
                                local_relpath,
                            )
                        recorded_existing += 1
                        print(f"[{index}/{total}] record existing: {local_relpath}")
                        continue

                    skipped_local += 1
                    print(f"[{index}/{total}] skip local-exists: {local_relpath}")
                    continue

        if options.dry_run:
            pulled += 1
            print(f"[{index}/{total}] would pull: {remote_path} -> {local_path}")
            continue

        ok = pull_file(remote_path, local_path, remote_size, device_id=device_id)

        if ok:
            record_success(
                conn,
                remote_path,
                remote_size,
                remote_mtime,
                local_relpath,
            )
            pulled += 1
        else:
            failed += 1

    print()
    print(f"完成。总数={total}")
    print(f"拉取={pulled}")
    print(f"跳过：已记录={skipped_logged}")
    print(f"跳过：本地已有但未记录={skipped_local}")
    print(f"补记日志={recorded_existing}")
    print(f"失败={failed}")

    return {
        "total": total,
        "pulled": pulled,
        "skipped_logged": skipped_logged,
        "skipped_local": skipped_local,
        "recorded_existing": recorded_existing,
        "failed": failed,
    }


def main():
    parser = argparse.ArgumentParser(
        description="从 Android 相机目录导出照片；用日志避免重复导出已处理过的文件。"
    )

    parser.add_argument(
        "--remote",
        default=None,
        help=f"手机端来源目录。设置后只运行一个命令行任务；默认：{DEFAULT_REMOTE_DIR}",
    )

    parser.add_argument(
        "--local",
        default=None,
        help=f"本地目标目录。设置后只运行一个命令行任务；默认：{DEFAULT_LOCAL_DIR}",
    )

    parser.add_argument(
        "--db",
        default=None,
        help=f"日志数据库路径。默认：{DEFAULT_DB_PATH}",
    )

    parser.add_argument(
        "--config",
        default=None,
        help=f"配置文件路径。默认：{DEFAULT_CFG_PATH}",
    )

    add_boolean_arg(
        parser,
        "dry-run",
        help="只显示将要执行的操作，不实际复制，不写入日志。",
    )

    add_boolean_arg(
        parser,
        "fast",
        help="快速模式：只按文件名判断是否传过，不读取远端 size/mtime。",
    )

    add_boolean_arg(
        parser,
        "retransfer-deleted",
        help="如果日志显示传过，但本地文件已删除，则重新传输。fast 模式下同样生效。",
    )

    add_boolean_arg(
        parser,
        "force",
        help="忽略日志和本地文件状态，强制重新传输所有远端文件。",
    )

    add_boolean_arg(
        parser,
        "record-existing",
        help="本地已有且大小一致但日志没有记录时，直接写入日志，不重新传输。fast 模式下只按文件名补记。",
    )

    args = parser.parse_args()

    app_config = load_app_config(args)

    check_adb(device_id=app_config.device_id)

    conn = connect_db(app_config.db_path)

    print(f"配置：{Path(args.config).expanduser() if args.config else DEFAULT_CFG_PATH}")
    print(f"日志：{app_config.db_path}")
    print(f"ADB 设备：{app_config.device_id or '默认'}")
    print()

    summaries = []
    job_count = len(app_config.jobs)

    for job_number, job in enumerate(app_config.jobs, start=1):
        summaries.append(
            run_job(
                job,
                conn,
                app_config.options,
                device_id=app_config.device_id,
                job_number=job_number,
                job_count=job_count,
            )
        )

        if job_number < job_count:
            print()

    if job_count > 1:
        print()
        print("全部任务完成。")
        print(f"总数={sum(item['total'] for item in summaries)}")
        print(f"拉取={sum(item['pulled'] for item in summaries)}")
        print(f"跳过：已记录={sum(item['skipped_logged'] for item in summaries)}")
        print(f"跳过：本地已有但未记录={sum(item['skipped_local'] for item in summaries)}")
        print(f"补记日志={sum(item['recorded_existing'] for item in summaries)}")
        print(f"失败={sum(item['failed'] for item in summaries)}")


if __name__ == "__main__":
    main()
