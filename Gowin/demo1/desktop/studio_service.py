"""Newline JSON sidecar, one response per request, stdout reserved for IPC."""
import argparse
import json
from pathlib import Path
import queue
import sys
import threading

from studio_engine import StudioEngine


def serve(engine, source=sys.stdin, sink=sys.stdout):
    requests = queue.Queue(maxsize=64)

    def read_input():
        while True:
            line = source.readline(2 * 1024 * 1024 + 1)
            requests.put(line)
            if not line:
                return

    threading.Thread(target=read_input, daemon=True).start()
    try:
        while True:
            engine.tick()
            try:
                line = requests.get(timeout=.03)
            except queue.Empty:
                continue
            if not line:
                break
            try:
                if len(line) > 2 * 1024 * 1024:
                    raise ValueError('请求过大。')
                request = json.loads(line, parse_constant=lambda _: (_ for _ in ()).throw(ValueError('无效数值。')))
                if not isinstance(request, dict):
                    raise ValueError('请求必须为对象。')
                if request.get('method') == 'shutdown':
                    break
                result = engine.dispatch(request.get('method'), request.get('params', {}))
                response = dict(ok=True, result=result)
            except (ValueError, TypeError, KeyError, OSError, RuntimeError) as error:
                response = dict(ok=False, error=str(error))
            sink.write(json.dumps(response, ensure_ascii=False, allow_nan=False) + '\n')
            sink.flush()
    finally:
        engine.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--config', type=Path)
    args = parser.parse_args()
    sys.stdin.reconfigure(encoding='utf-8')
    sys.stdout.reconfigure(encoding='utf-8')
    serve(StudioEngine(args.assets, args.config))
