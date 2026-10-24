# Reprints the corpus's Word references on Word for Windows, into
# test/corpus/docx/word-win/<key>-orig.pdf, one per key that has a Mac print
# in test/corpus/docx/word.
#
#   python -I test/docx-word-win-reprint.py [--batch 40] [--hang 600] [--retry] [KEY…]
#
# Word runs in batches (test/docx-word-win-worker.ps1), a fresh Word for each,
# so one long-lived process cannot drift. A key already printed is skipped, so
# a run stopped halfway (out of memory, a reboot) resumes where it was; one
# that failed is skipped too, unless --retry. A document Word sits on for
# --hang seconds is logged as hung, its Word killed, and the batch restarted
# after it. Everything goes to word-win/reprint.log, one line per key:
#   <key>\tok\t<pages>\t<seconds>   or   <key>\terror|hung\t<message>
# The scorer reads this folder with DOCX_WORD_REFS=test/corpus/docx/word-win.
import os, sys, subprocess, threading, queue, time, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(HERE, 'corpus', 'docx', 'docs')
MAC = os.path.join(HERE, 'corpus', 'docx', 'word')
OUT = os.path.join(HERE, 'corpus', 'docx', 'word-win')
LOG = os.path.join(OUT, 'reprint.log')
WORKER = os.path.join(HERE, 'docx-word-win-worker.ps1')

args = sys.argv[1:]
def opt(name, default):
    if name in args:
        i = args.index(name); v = args[i + 1]; del args[i:i + 2]; return type(default)(v)
    return default
batch, hang = opt('--batch', 40), opt('--hang', 600)
retry = '--retry' in args
if retry: args.remove('--retry')
os.makedirs(OUT, exist_ok=True)

keys = args or sorted(f[:-len('-orig.pdf')] for f in os.listdir(MAC) if f.endswith('-orig.pdf'))
failed = set()
if os.path.exists(LOG):
    for line in open(LOG, encoding='utf-8'):
        f = line.rstrip('\n').split('\t')
        if len(f) > 1 and f[1] != 'ok': failed.add(f[0])
        elif len(f) > 1: failed.discard(f[0])
todo = [k for k in keys if not os.path.exists(os.path.join(OUT, k + '-orig.pdf')) and (retry or k not in failed)]
print(f'{len(keys)} keys, {len(keys) - len(todo)} done or failed, {len(todo)} to print', flush=True)

def log(*f):
    with open(LOG, 'a', encoding='utf-8') as g: g.write('\t'.join(str(x) for x in f) + '\n')

def kill(pid):
    if pid: subprocess.run(['taskkill', '/F', '/T', '/PID', str(pid)], capture_output=True)

t_start, n_done = time.time(), 0
while todo:
    chunk, todo = todo[:batch], todo[batch:]
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False, encoding='utf-8') as f:
        f.write('\n'.join(chunk) + '\n'); keyfile = f.name
    p = subprocess.Popen(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', WORKER,
                          '-Keys', keyfile, '-Docs', DOCS, '-Out', OUT],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
    lines = queue.Queue()
    threading.Thread(target=lambda: ([lines.put(l) for l in p.stdout], lines.put(None)), daemon=True).start()
    word, current, since, seen = None, None, time.time(), set()
    while True:
        try: line = lines.get(timeout=5)
        except queue.Empty:
            if current and time.time() - since > hang:
                log(current, 'hung', f'no answer in {hang}s')
                print(f'  {current}: hung, killing Word {word}', flush=True)
                seen.add(current); kill(word); kill(p.pid)
                break
            continue
        if line is None: break
        w = line.rstrip('\n').split(' ', 2)
        if w[0] == 'word': word = int(w[1])
        elif w[0] == 'start': current, since = w[1], time.time()
        elif w[0] in ('ok', 'error') and len(w) > 1:
            seen.add(w[1]); current = None; n_done += 1
            if w[0] == 'ok':
                pages, sec = (w[2].split(' ') + ['', ''])[:2]
                log(w[1], 'ok', pages, sec)
            else:
                log(w[1], 'error', w[2] if len(w) > 2 else '')
                print(f'  {w[1]}: error {w[2] if len(w) > 2 else ""}', flush=True)
        elif w[0] == 'fatal':
            print(line.rstrip(), flush=True)
        elif line.strip():
            print('  worker:', line.rstrip(), flush=True)
    p.wait(timeout=60) if p.poll() is None else None
    # Quit() asks, and Word stays: a run of batches would leave one each.
    time.sleep(3); kill(word)
    os.unlink(keyfile)
    if not seen:
        sys.exit('a batch printed nothing: stopping rather than starting Word again and again')
    # Whatever the batch never reached goes back on the list, after the hung one.
    todo = [k for k in chunk if k not in seen and not os.path.exists(os.path.join(OUT, k + '-orig.pdf'))] + todo
    el = time.time() - t_start
    print(f'{n_done} printed or failed, {len(todo)} left, {el / 60:.1f} min', flush=True)
print('done', flush=True)
