import faulthandler
import logging
import platform
import sys
import threading
from logging.handlers import RotatingFileHandler
from pathlib import Path
from types import TracebackType

from PySide6.QtCore import (
    QMessageLogContext,
    QStandardPaths,
    QtMsgType,
    qInstallMessageHandler,
)
from PySide6.QtWidgets import QApplication

from . import __version__

_configured = False
_log_file_path: Path | None = None
_crash_log_file = None


def _safe_exc_info(
    exc_type: type[BaseException],
    exc_value: BaseException | None,
    exc_traceback: TracebackType | None,
) -> (
    tuple[type[BaseException], BaseException, TracebackType | None]
    | tuple[None, None, None]
):
    """Normalize exception tuple for logging APIs that require non-optional exception values."""
    if exc_value is None:
        return (None, None, None)
    return (exc_type, exc_value, exc_traceback)


def _install_exception_hooks() -> None:
    def exc_hook(
        exc_type: type[BaseException], exc: BaseException, tb: TracebackType | None
    ) -> None:
        logging.getLogger("uncaught").critical(
            "Uncaught exception",
            exc_info=(exc_type, exc, tb),
        )

    sys.excepthook = exc_hook

    def thread_exc_hook(args: threading.ExceptHookArgs) -> None:
        logging.getLogger("uncaught").critical(
            "Uncaught thread exception",
            exc_info=_safe_exc_info(args.exc_type, args.exc_value, args.exc_traceback),
        )

    threading.excepthook = thread_exc_hook

    def unraisable_hook(args: sys.UnraisableHookArgs) -> None:
        logging.getLogger("uncaught").error(
            "Unraisable exception in %r",
            args.object,
            exc_info=_safe_exc_info(args.exc_type, args.exc_value, args.exc_traceback),
        )

    sys.unraisablehook = unraisable_hook


def setup_bootstrap_logging() -> None:
    root = logging.getLogger()
    if root.handlers:
        _install_exception_hooks()
        return

    fmt = logging.Formatter("%(asctime)s ¦ %(levelname)s ¦ %(name)s ¦ %(message)s")
    sh = logging.StreamHandler(sys.stderr)
    sh.setLevel(logging.INFO)
    sh.setFormatter(fmt)
    root.setLevel(logging.DEBUG)
    root.addHandler(sh)
    _install_exception_hooks()


def setup_logging(_app: QApplication) -> Path:
    global _configured, _log_file_path, _crash_log_file
    if _configured:
        assert _log_file_path is not None
        return _log_file_path

    base = Path(
        QStandardPaths.writableLocation(
            QStandardPaths.StandardLocation.AppLocalDataLocation
        )
    )
    log_dir = base / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "dbs-annotator.log"

    fmt = logging.Formatter("%(asctime)s ¦ %(levelname)s ¦ %(name)s ¦ %(message)s")
    root = logging.getLogger()
    root.setLevel(logging.DEBUG)
    for h in root.handlers[:]:
        root.removeHandler(h)

    fh = RotatingFileHandler(
        log_path, maxBytes=5_000_000, backupCount=3, encoding="utf-8"
    )
    fh.setLevel(logging.INFO)
    fh.setFormatter(fmt)
    root.addHandler(fh)

    if not getattr(sys, "frozen", False):
        sh = logging.StreamHandler(sys.stderr)
        sh.setLevel(logging.INFO)
        sh.setFormatter(fmt)
        root.addHandler(sh)

    _install_exception_hooks()

    def qt_handler(mode: QtMsgType, context: QMessageLogContext, message: str) -> None:
        if mode == QtMsgType.QtDebugMsg:
            level = logging.DEBUG
        elif mode == QtMsgType.QtInfoMsg:
            level = logging.INFO
        elif mode == QtMsgType.QtWarningMsg:
            level = logging.WARNING
        elif mode == QtMsgType.QtCriticalMsg:
            level = logging.ERROR
        else:
            level = logging.CRITICAL
        suffix = ""
        if context.file:
            suffix = f" ({context.file}:{context.line})"
        logging.getLogger("qt").log(level, "%s%s", message, suffix)

    qInstallMessageHandler(qt_handler)
    _app.aboutToQuit.connect(
        lambda: logging.getLogger("dbs_annotator").info("Application shutdown")
    )

    crash_log_path = log_dir / "dbs-annotator-crash.log"
    try:
        _crash_log_file = open(crash_log_path, "a", encoding="utf-8")
        faulthandler.enable(file=_crash_log_file, all_threads=True)
    except Exception:
        logging.getLogger("dbs_annotator").exception(
            "Failed to enable faulthandler with crash log %s",
            crash_log_path,
        )

    logging.getLogger("dbs_annotator").info(
        "Started v%s Python %s | %s | log=%s",
        __version__,
        platform.python_version(),
        platform.platform(),
        log_path.resolve(),
    )

    resolved = log_path.resolve()
    _configured = True
    _log_file_path = resolved
    return resolved
