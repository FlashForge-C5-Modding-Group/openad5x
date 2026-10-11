import sys, os, io, tarfile, zipfile

build = os.path.dirname(os.path.abspath(__file__))
f001 = sys.argv[1]
out = os.path.join(build, 'fluidd-ad5x.tar.gz')

def add(tf, data, arcname, mode=0o644):
    ti = tarfile.TarInfo(arcname)
    ti.size = len(data); ti.mode = mode
    tf.addfile(ti, io.BytesIO(data))

with tarfile.open(out, 'w:gz') as tf:
    add(tf, open(os.path.join(f001, 'usr/sbin/nginx'), 'rb').read(), 'nginx/nginx', 0o755)
    add(tf, open(os.path.join(f001, 'etc/nginx/mime.types'), 'rb').read(), 'nginx/mime.types')
    add(tf, open(os.path.join(build, 'nginx.conf'), 'rb').read(), 'nginx/nginx.conf')
    z = zipfile.ZipFile(os.path.join(build, 'dl', 'fluidd.zip'))
    for n in z.namelist():
        if n.endswith('/'):
            continue
        add(tf, z.read(n), 'fluidd/' + n)
print(out, os.path.getsize(out))
