#!/usr/bin/env python3
import sys
import argparse

def generate_const_array(data, status):
    name = f"response_{status}"
    if status == 200:
        name = "response_main"
    elif status == 302:
        name = "response_redirect"
    elif status == 201:
        name = "response_status"
    elif status == 404:
        name = "response_404"
        
    # Format nicely with 12 bytes per line
    lines = []
    chunk_size = 12
    for i in range(0, len(data), chunk_size):
        chunk = data[i:i+chunk_size]
        bytes_str = ", ".join(f"{b:3d}" for b in chunk)
        lines.append(f"    {bytes_str}")
        
    body_str = ",\n".join(lines)
    return f"static const _BitInt(8) {name}[RESPONSE_LEN_{status}] = {{\n{body_str}\n}};"

def main():
    parser = argparse.ArgumentParser(description="Generate C const array fragments for HTTP responses")
    parser.add_argument("--status", type=int, required=True, choices=[200, 302, 404, 201], help="HTTP status code to generate")
    parser.add_argument("html_file", nargs="?", help="Input HTML file path (required for 200)")
    
    args = parser.parse_args()
    
    headers = ""
    body = b""
    
    if args.status == 200:
        if not args.html_file:
            print("Error: Input HTML file is required for status 200", file=sys.stderr)
            sys.exit(1)
        with open(args.html_file, "rb") as f:
            body = f.read()
        headers = (
            "HTTP/1.0 200 OK\r\n"
            "Content-Type: text/html\r\n"
            f"Content-Length: {len(body)}\r\n"
            "Connection: close\r\n"
            "\r\n"
        )
    elif args.status == 201:
        # Custom status JSON endpoint /s
        body = b'{"led0":0,"led1":0}'
        headers = (
            "HTTP/1.0 200 OK\r\n"
            "Content-Type: application/json\r\n"
            f"Content-Length: {len(body)}\r\n"
            "Connection: close\r\n"
            "\r\n"
        )
    elif args.status == 302:
        headers = (
            "HTTP/1.0 302 Found\r\n"
            "Location: /\r\n"
            "Content-Length: 0\r\n"
            "Connection: close\r\n"
            "\r\n"
        )
    elif args.status == 404:
        body = b"Not Found"
        headers = (
            "HTTP/1.0 404 Not Found\r\n"
            "Content-Type: text/plain\r\n"
            f"Content-Length: {len(body)}\r\n"
            "Connection: close\r\n"
            "\r\n"
        )
        
    full_response = headers.encode("utf-8") + body
    
    print(f"// Auto-generated HTTP response constant array (Status: {args.status})")
    print(f"// Total response length: {len(full_response)} bytes")
    print(f"#define RESPONSE_LEN_{args.status} {len(full_response)}")
    print("")
    
    print(generate_const_array(full_response, args.status))

    # Also automatically write out corresponding .mem file for Verilog ROM
    mem_filename = f"response_{args.status}.mem"
    if args.status == 200:
        mem_filename = "response_main.mem"
    elif args.status == 302:
        mem_filename = "response_redirect.mem"
    elif args.status == 201:
        mem_filename = "response_status.mem"
    elif args.status == 404:
        mem_filename = "response_404.mem"

    with open(mem_filename, "w") as f:
        for b in full_response:
            f.write(f"{b:02x}\n")

if __name__ == "__main__":
    main()
