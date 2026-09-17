#!/usr/bin/env python3
import sys
import time
import socket
import argparse
import serial

def main():
    parser = argparse.ArgumentParser(description="Hotwright FPGA Web Server Transparent TCP-to-UART Bridge")
    parser.add_argument("--port", type=int, default=8080, help="TCP port to listen on (default: 8080)")
    parser.add_argument("--serial-port", type=str, default="/dev/ttyUSB1", help="Serial port of the FPGA (default: /dev/ttyUSB1)")
    parser.add_argument("--baud", type=int, default=115200, help="UART baud rate (default: 115200)")
    parser.add_argument("--timeout", type=float, default=0.05, help="Serial idle read timeout in seconds (default: 0.05)")
    
    args = parser.parse_args()
    
    # 1. Connect to FPGA Serial Port
    print(f"[*] Opening serial port: {args.serial_port} @ {args.baud} baud...")
    try:
        ser = serial.Serial(
            port=args.serial_port,
            baudrate=args.baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.01  # non-blocking read
        )
    except Exception as e:
        print(f"[!] Error opening serial port: {e}", file=sys.stderr)
        print("[!] Make sure the FPGA is plugged in and you have read/write access to the device.", file=sys.stderr)
        sys.exit(1)
        
    # 2. Bind TCP Server Socket
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
    try:
        server_socket.bind(('0.0.0.0', args.port))
    except Exception as e:
        print(f"[!] Error binding TCP port {args.port}: {e}", file=sys.stderr)
        sys.exit(1)
        
    server_socket.listen(5)
    print(f"[*] Bridge server successfully started on: http://localhost:{args.port}")
    print("[*] Waiting for browser requests...")
    
    try:
        while True:
            # Accept a browser connection
            client_socket, client_address = server_socket.accept()
            print(f"\n[+] Client connected from {client_address[0]}:{client_address[1]}")
            client_socket.settimeout(0.2)  # non-blocking socket reads
            
            try:
                # Read all incoming HTTP request bytes
                request_data = b""
                while True:
                    try:
                        chunk = client_socket.recv(1024)
                        if not chunk:
                            break
                        request_data += chunk
                        if len(chunk) < 1024:
                            break
                    except socket.timeout:
                        break
                
                if not request_data:
                    client_socket.close()
                    continue
                    
                print(f"[>] HTTP Request ({len(request_data)} bytes):")
                # Print headers in green
                try:
                    print("\033[92m" + request_data.decode("utf-8").strip() + "\033[0m")
                except UnicodeDecodeError:
                    print(request_data)
                
                # Flush existing stale serial buffers
                ser.reset_input_buffer()

                # Forward HTTP request bytes to FPGA via UART, paced in
                # small chunks rather than one big write(). A single fast
                # unpaced write of a real ~500-byte browser request (many
                # headers) reproducibly corrupted/truncated the response
                # -- root-caused host-side, not an FPGA bug: identical
                # request bytes sent with a 2ms/byte software pace (well
                # past the 87us/byte line time at 115200 baud) came back
                # byte-for-byte correct every time, and starting the
                # response read on a background thread before the write
                # (closing any write/read overlap gap) made no difference,
                # which rules that theory out. Most consistent with the
                # FTDI chip's own onboard TX buffer overflowing on a fast
                # burst past a small threshold (measured ~68 OK / 84
                # corrupt bytes) -- short writes never hit it, which is
                # why this went unnoticed until a real multi-header
                # browser request was tested. Chunking keeps normal
                # requests fast while staying well under that threshold
                # per write() call.
                print("[*] Forwarding request to FPGA...")
                CHUNK = 32
                for i in range(0, len(request_data), CHUNK):
                    ser.write(request_data[i:i + CHUNK])
                    ser.flush()
                    if i + CHUNK < len(request_data):
                        time.sleep(0.005)

                # Read response bytes from FPGA
                print("[*] Reading response from FPGA...")
                response_data = b""
                last_recv_time = time.time()

                while True:
                    char = ser.read(1)
                    if char:
                        response_data += char
                        last_recv_time = time.time()
                    else:
                        # Idle timeout check
                        if time.time() - last_recv_time > args.timeout:
                            break

                if response_data:
                    print(f"[<] FPGA Response ({len(response_data)} bytes):")
                    # Try to print first few lines of response
                    try:
                        resp_preview = response_data[:100].decode("utf-8").strip()
                        print("\033[94m" + resp_preview + " ...\033[0m")
                    except UnicodeDecodeError:
                        print(response_data[:100])
                    
                    # Forward response back to the client browser
                    client_socket.sendall(response_data)
                else:
                    print("[!] No response received from FPGA.")
                    
            except Exception as e:
                print(f"[!] Error handling request: {e}")
            finally:
                client_socket.close()
                print("[-] Connection closed.")
                
    except KeyboardInterrupt:
        print("\n[*] Shutting down bridge.")
    finally:
        server_socket.close()
        ser.close()

if __name__ == "__main__":
    main()
