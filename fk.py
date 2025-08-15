import argparse
import base64
import json
import os
import re
import sys
from pathlib import Path

from google import genai
from google.genai import types
API_KEY = os.environ.get("GEMINI_API_KEY")

PROMPT_TMPL = """You are a command-line fixer for {shell} on Windows.
Given the user's last command and the error output, return ONLY a compact JSON object:
{{
  "command": "<single line fixed command or empty if none>",
  "reason": "<short reason>"
}}
Rules:
- Target shell: {shell} (Windows). Do NOT add 'sudo'.
- Keep paths properly quoted for PowerShell if needed.
- Prefer minimal fixes (typo, missing flag, right subcommand).
- If the command seems to be correct in linux, suggest the same command for Windows.
- If not confident, return the most likely command.
- If the command is not recognized as a valid command, suggest install the missing in the reason.
- If the powershell command's parameter is not matched, suggest the correct parameter.
- If the last_command is like to ask for something, suggest the command to achieve the user goal.
Input:
last_command: ```{last}```
error_output: ```{err}```
"""

def get_config_path():
    """Get the path to the config file"""
    home = Path.home()
    config_dir = home / ".config" / "fk"
    config_dir.mkdir(parents=True, exist_ok=True)
    return config_dir / "config.json"


def load_config():
    """Load configuration from file"""
    config_path = get_config_path()
    default_config = {
        "temperature": 1.2,
        "max_output_tokens": 1024,
        "auto_confirm": False,
        "model": "gemini-2.5-flash"
    }

    if not config_path.exists():
        return default_config

    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        for key, value in default_config.items():
            if key not in config:
                config[key] = value
        return config
    except (json.JSONDecodeError, IOError):
        return default_config


def save_config(config):
    """Save configuration to file"""
    config_path = get_config_path()
    try:
        with open(config_path, 'w') as f:
            json.dump(config, f, indent=2)
        return True
    except IOError:
        return False


def validate_config_value(key, value):
    """Validate configuration values"""
    if key == "temperature":
        try:
            temp = float(value)
            if 0.0 <= temp <= 2.0:
                return temp
            else:
                raise ValueError("Between 0.0 and 2.0")
        except ValueError as e:
            if "could not convert" in str(e):
                raise ValueError("Temperature must be a number")
            raise
    elif key == "max_output_tokens":
        try:
            tokens = int(value)
            if 1 <= tokens <= 8192:
                return tokens
            else:
                raise ValueError(
                    "Max output tokens must be between 1 and 8192")
        except ValueError as e:
            if "invalid literal" in str(e):
                raise ValueError("Max output tokens must be an integer")
            raise
    elif key == "auto_confirm":
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            if value.lower() in ["true", "yes", "1", "on"]:
                return True
            elif value.lower() in ["false", "no", "0", "off"]:
                return False
            else:
                raise ValueError(
                    "Phải là true/false, yes/no, 1/0, on/off")
        raise ValueError("Phải là boolean hoặc string")
    elif key == "model":
        if not isinstance(value, str) or not value.strip():
            raise ValueError("Không được để trống")
        return value.strip()
    else:
        raise ValueError(f"Không tìm thấy: {key}")


def handle_config_command(args):
    """Handle the config subcommand"""
    config = load_config()

    if not args.key:
        print("Cấu hình hiện tại:")
        for key, value in config.items():
            print(f"  {key}: {value}")
        return

    if not args.value:
        if args.key in config:
            print(f"{args.key}: {config[args.key]}")
        else:
            print(f"Không tìm thấy cấu hình: {args.key}")
            sys.exit(1)
        return

    try:
        validated_value = validate_config_value(args.key, args.value)
        config[args.key] = validated_value
        if save_config(config):
            print(f"Đã cập nhật: {args.key} = {validated_value}")
        else:
            print("Lỗi: Không thể lưu")
            sys.exit(1)
    except ValueError as e:
        print(f"Lỗi: {e}")
        sys.exit(1)


def b64dec(s):
    return base64.b64decode(s.encode('utf-8')).decode('utf-8') if s else ""


def extract_json(text: str):
    m = re.search(r'\{.*\}', text, flags=re.S)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser(
        description="Công cụ sửa lỗi dòng lệnh Powershell")

    subparsers = ap.add_subparsers(dest='command', help='Các lệnh có sẵn')

    config_parser = subparsers.add_parser(
        'config', help='Quản lý cấu hình')
    config_parser.add_argument(
        'key', nargs='?', help='Cấu hình')
    config_parser.add_argument(
        'value', nargs='?', help='Giá trị')

    ap.add_argument("--shell", default="powershell")
    ap.add_argument("--cmd-b64")
    ap.add_argument("--err-b64", default="")
    ap.add_argument("--model")
    ap.add_argument("--temperature", type=float)
    ap.add_argument("--max-output-tokens", type=int)
    ap.add_argument("--auto-confirm", action="store_true")

    args = ap.parse_args()

    if args.command == 'config':
        handle_config_command(args)
        return

    if not args.cmd_b64:
        ap.error("--cmd-b64 is required")

    if not API_KEY:
        print(json.dumps({"error": "GEMINI_API_KEY is not set"}))
        sys.exit(2)

    client = genai.Client(api_key=API_KEY)

    config = load_config()

    model = args.model or config["model"]
    temperature = args.temperature if args.temperature is not None else config["temperature"]
    max_output_tokens = getattr(args, 'max_output_tokens') if getattr(
        args, 'max_output_tokens') is not None else config["max_output_tokens"]
    auto_confirm = args.auto_confirm or config["auto_confirm"]

    last = b64dec(args.cmd_b64)
    err = b64dec(args.err_b64)
    prompt = PROMPT_TMPL.format(shell=args.shell, last=last, err=err)

    try:
        resp = client.models.generate_content(
            model=model,
            contents=prompt,
            config=types.GenerateContentConfig(
                temperature=temperature, max_output_tokens=max_output_tokens)
        )
        text = getattr(resp, "text", "") or ""
        data = extract_json(text) or {}
    except Exception as e:
        print(json.dumps({"error": f"Gemini error: {e}"}))
        sys.exit(3)

    cmd = (data.get("command") or "").strip()
    reason = (data.get("reason") or "").strip()

    if not cmd:
        print(json.dumps(
            {"command": "", "reason": reason or "No confident fix"}))
        return

    # if is_dangerous(cmd):
    #     print(json.dumps({"command": "", "reason": "Blocked potentially destructive command"}))
    #     return

    output = {"command": cmd, "reason": reason}
    if auto_confirm:
        output["auto_confirm"] = True
    print(json.dumps(output))


if __name__ == "__main__":
    main()
