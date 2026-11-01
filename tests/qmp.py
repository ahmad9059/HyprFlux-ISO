"""Minimal QMP client used only by the disposable test harness."""
import json
import socket


def request(path, command, arguments=None):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(5)
        connection.connect(str(path))
        stream = connection.makefile("rwb", buffering=0)
        greeting = json.loads(stream.readline())
        if "QMP" not in greeting:
            raise RuntimeError("Invalid QMP greeting")
        for name in ("qmp_capabilities", command):
            payload = {"execute": name}
            if name == command and arguments is not None:
                payload["arguments"] = arguments
            stream.write(json.dumps(payload).encode() + b"\n")
            while True:
                line = stream.readline()
                if not line:
                    raise RuntimeError("QMP connection closed")
                result = json.loads(line)
                if "error" in result:
                    raise RuntimeError(result["error"])
                if "return" in result:
                    break
        return result["return"]
