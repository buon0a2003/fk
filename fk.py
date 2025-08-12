# C:\tools\fk\fk.py
import argparse, base64, json, os, re, sys

# --- Gemini client (google-genai) ---
from google import genai
from google.genai import types
API_KEY = os.environ.get("GEMINI_API_KEY")
# API_KEY = "AIzaSyA4bkq1M-Fb9bGUpDWWVU6rK_0Rweqxu7E"
if not API_KEY:
    print(json.dumps({"error": "GEMINI_API_KEY is not set"}))
    sys.exit(2)
client = genai.Client(api_key=API_KEY)

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

def b64dec(s): 
    return base64.b64decode(s.encode('utf-8')).decode('utf-8') if s else ""

def extract_json(text: str):
    # try to find first {...} JSON block
    m = re.search(r'\{.*\}', text, flags=re.S)
    if not m: 
        return None
    try:
        return json.loads(m.group(0))
    except Exception:
        return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shell", default="powershell")
    ap.add_argument("--cmd-b64", required=True)
    ap.add_argument("--err-b64", default="")
    ap.add_argument("--model", default="gemini-2.5-flash")
    args = ap.parse_args()

    last = b64dec(args.cmd_b64)
    err = b64dec(args.err_b64)
    prompt = PROMPT_TMPL.format(shell=args.shell, last=last, err=err)

    try:
        resp = client.models.generate_content(
            model=args.model,
            contents=prompt,
            config=types.GenerateContentConfig(temperature=1.2, max_output_tokens=1024)
        )
        text = getattr(resp, "text", "") or ""
        data = extract_json(text) or {}
    except Exception as e:
        print(json.dumps({"error": f"Gemini error: {e}"}))
        sys.exit(3)

    cmd = (data.get("command") or "").strip()
    reason = (data.get("reason") or "").strip()

    if not cmd:
        print(json.dumps({"command": "", "reason": reason or "No confident fix"}))
        return

    # if is_dangerous(cmd):
    #     print(json.dumps({"command": "", "reason": "Blocked potentially destructive command"}))
    #     return

    # Output strict JSON for PowerShell to parse
    print(json.dumps({"command": cmd, "reason": reason}))

if __name__ == "__main__":
    main()
