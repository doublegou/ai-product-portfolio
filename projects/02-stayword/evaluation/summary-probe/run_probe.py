"""Diagnostic probe of bundled weights on macOS, not an iOS end-to-end benchmark.
Run from any cwd: python run_probe.py --output results.json
Fixtures are authored synthetic transcripts. No private audio leaves this machine.
"""
import argparse, hashlib, importlib.metadata, json, platform, re, subprocess, textwrap, time
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
import mlx.core as mx
from mlx_lm import load, stream_generate
from mlx_lm.sample_utils import make_sampler, make_logits_processors

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
SOURCE = PROJECT / 'src/stayword-front-ios/StayWord/Services/SummaryService.swift'
MODEL = PROJECT / 'src/stayword-front-ios/StayWord/Resources/Models/Summary/Qwen3.5-0.8B-MLX-4bit'

def file_sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1048576), b''): h.update(chunk)
    return h.hexdigest()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, default=HERE/'results.json')
    ap.add_argument('--cases', type=Path, default=HERE/'cases.json')
    ap.add_argument('--candidate', action='store_true')
    args = ap.parse_args()
    code = SOURCE.read_text()
    system = textwrap.dedent(re.search(r'private static let systemInstructions = """\n(.*?)\n        """', code, re.S)[1])
    template = textwrap.dedent(re.search(r'private static func singleDocumentPrompt\(for text: String\).*?"""\n(.*?)\n        """', code, re.S)[1])
    fixtures = json.loads(args.cases.read_text())
    if args.candidate:
        system += '\n\n' + (HERE/'candidate-policy.txt').read_text()
    started = time.perf_counter()
    model, tokenizer = load(str(MODEL))
    result = {
        'run_date': datetime.now(ZoneInfo('Asia/Shanghai')).date().isoformat(), 'environment': {'os': platform.platform(), 'chip': subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string']).decode().strip()},
        'scope': 'macOS Python MLX; bundled weights + extracted iOS single-document prompts; synthetic text only, no ASR/audio, UI, phone performance, multi-chunk pipeline or production traffic',
        'versions': {p:importlib.metadata.version(p) for p in ['mlx','mlx-lm','transformers']},
        'source_sha256':file_sha(SOURCE),'weights_sha256':file_sha(MODEL/'model.safetensors'),
        'cases_sha256':file_sha(args.cases), 'variant': 'candidate' if args.candidate else 'source',
        'candidate_policy_sha256':file_sha(HERE/'candidate-policy.txt') if args.candidate else None,
        'settings':{'seeds':[17,29],'temperature':0.2,'top_p':0.9,'repetition_penalty':1.05,'repetition_context_size':64,'enable_thinking':False,'max_tokens':1024,'note':'1024-token safety cap differs from iOS final generation; timing excludes initial model load'},
        'model_load_seconds':round(time.perf_counter()-started,3), 'results':[]}
    for case in fixtures:
        for seed in [17,29]:
            mx.random.seed(seed)
            prompt = tokenizer.apply_chat_template([{'role':'system','content':system},{'role':'user','content':template.replace('\\(text)',case['text'])}],tokenize=False,add_generation_prompt=True,enable_thinking=False)
            t0=time.perf_counter(); parts=[]; last=None
            for response in stream_generate(model,tokenizer,prompt,max_tokens=1024,sampler=make_sampler(temp=0.2,top_p=0.9),logits_processors=make_logits_processors(repetition_penalty=1.05,repetition_context_size=64)):
                parts.append(response.text); last=response
            entry={'id':case['id'],'seed':seed,'output':''.join(parts),'generation_seconds':round(time.perf_counter()-t0,3),'output_tokens':last.generation_tokens,'hit_token_cap':last.generation_tokens>=1024}
            result['results'].append(entry)
            args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
            print(case['id'],seed,entry['generation_seconds'],entry['output_tokens'],flush=True)
            mx.clear_cache()

if __name__ == '__main__': main()
