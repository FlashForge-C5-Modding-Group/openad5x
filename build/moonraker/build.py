import sys, os, tarfile, io

MR_COMMIT = 'abd2026b90d86fb738c6619be3ceefcedee2006c'
build = os.path.dirname(os.path.abspath(__file__))
mr_tgz = os.path.join(build, 'dl', 'moonraker.tar.gz')
saf_tgz = sys.argv[1]
f001 = sys.argv[2]
out = os.path.join(build, 'moonraker-ad5x.tar.gz')

SP = 'moonraker-env/lib/python3.8/site-packages/'
SKIP = ('pip', 'setuptools', 'wheel', 'virtualenv', 'distlib', 'filelock',
        'platformdirs', '_distutils_hack', 'distutils-precedence.pth',
        '_virtualenv')

def skip_pkg(rel):
    top = rel.split('/')[0]
    if '__pycache__' in rel or rel.endswith('.pyc'):
        return True
    for s in SKIP:
        if top == s or top.startswith(s + '-') and top.endswith('.dist-info'):
            return True
    return False

def add_file(tf, path, arcname, mode=0o644):
    data = open(path, 'rb').read()
    ti = tarfile.TarInfo(arcname)
    ti.size = len(data); ti.mode = mode; ti.uid = ti.gid = 0
    tf.addfile(ti, io.BytesIO(data))

with tarfile.open(out, 'w:gz') as tf:
    with tarfile.open(mr_tgz) as src:
        prefix = 'moonraker-' + MR_COMMIT
        for m in src.getmembers():
            if not m.name.startswith(prefix):
                continue
            m.name = 'moonraker' + m.name[len(prefix):]
            m.uid = m.gid = 0; m.uname = m.gname = 'root'
            tf.addfile(m, src.extractfile(m) if m.isfile() else None)
    with tarfile.open(saf_tgz) as src:
        for m in src.getmembers():
            if not m.name.startswith(SP) or m.name == SP.rstrip('/'):
                continue
            rel = m.name[len(SP):]
            if not rel or skip_pkg(rel):
                continue
            m.name = 'moonraker-env/site-packages/' + rel
            m.uid = m.gid = 0; m.uname = m.gname = 'root'
            tf.addfile(m, src.extractfile(m) if m.isfile() else None)
    ver = ('v0.9.3-' + MR_COMMIT[:7] + chr(10)).encode()
    ti = tarfile.TarInfo('moonraker/moonraker/.version')
    ti.size = len(ver); ti.mode = 0o644
    tf.addfile(ti, io.BytesIO(ver))
    for n in ('__init__.py', 'dbapi2.py', 'dump.py'):
        add_file(tf, os.path.join(f001, 'usr/lib/python3.8/sqlite3', n),
                 'moonraker-env/site-packages/sqlite3/' + n)
    add_file(tf, os.path.join(f001, 'usr/lib/python3.8/lib-dynload/_sqlite3.cpython-38-mipsel-linux-gnu.so'),
             'moonraker-env/site-packages/_sqlite3.cpython-38-mipsel-linux-gnu.so', 0o755)
    add_file(tf, os.path.join(f001, 'usr/lib/libsqlite3.so.0.8.6'), 'moonraker-env/lib/libsqlite3.so.0', 0o755)
    for n in ('libsodium.so.23', 'libsodium.so'):
        add_file(tf, os.path.join(f001, 'usr/lib/libsodium.so.23.3.0'), 'moonraker-env/lib/' + n, 0o755)
print(out, os.path.getsize(out))
