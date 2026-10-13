"""Bench-only proxy for column F. dcode talks the Responses API. llama-server maps empty
reasoning items and empty tool output to empty chat content, which its template rejects.
This drops empty reasoning items and replaces empty content or output with a space. usage: fix_empty_content.py <listen-port> <upstream-port>"""
import http.client, json, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN, UP = int(sys.argv[1]), int(sys.argv[2])


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        try:
            d = json.loads(body)
            for m in d.get("messages", []):
                if m.get("content") in ("", None, []):
                    m["content"] = " "
            if isinstance(d.get("input"), list):
                items = d["input"]
                for a, b in zip(items, items[1:]):
                    # llama-server streams tool arguments into the reasoning item; move them to the call.
                    if a.get("type") == "reasoning" and a.get("arguments") and b.get("type") == "function_call" and not b.get("arguments"):
                        b["arguments"] = a.pop("arguments")
                d["input"] = [i for i in d["input"] if not (i.get("type") == "reasoning" and not i.get("content") and not i.get("summary"))]
                for i in d["input"]:
                    if i.get("type") == "function_call_output" and i.get("output") in ("", None):
                        i["output"] = " "
            body = json.dumps(d).encode()
        except ValueError:
            pass
        c = http.client.HTTPConnection("127.0.0.1", UP, timeout=900)
        c.request("POST", self.path, body, {k: v for k, v in self.headers.items() if k.lower() not in ("content-length", "host")} | {"Content-Length": str(len(body))})
        r = c.getresponse()
        self.send_response(r.status)
        for k, v in r.getheaders():
            if k.lower() not in ("transfer-encoding", "connection", "content-length"):
                self.send_header(k, v)
        self.send_header("Connection", "close")
        self.end_headers()
        while chunk := r.read1(4096):
            self.wfile.write(chunk)
            self.wfile.flush()

    def log_message(self, *a):
        pass


ThreadingHTTPServer(("127.0.0.1", LISTEN), H).serve_forever()
