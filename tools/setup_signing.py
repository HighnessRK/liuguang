from pathlib import Path
import os
import secrets
import subprocess

root = Path(__file__).resolve().parents[1]
properties = root / 'android/key.properties'
directory = root / '.signing'
keystore = directory / 'liuguang-release.jks'
if properties.exists() or keystore.exists():
    print('Existing signing material preserved.')
else:
    directory.mkdir(exist_ok=True)
    password = secrets.token_urlsafe(32)
    env = dict(os.environ, LIUGUANG_SIGNING_PASSWORD=password)
    subprocess.run([
        r'E:\ProgramFiles\Android\jbr\bin\keytool.exe', '-genkeypair',
        '-alias', 'liuguang', '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000',
        '-keystore', str(keystore), '-storepass:env', 'LIUGUANG_SIGNING_PASSWORD',
        '-keypass:env', 'LIUGUANG_SIGNING_PASSWORD', '-dname', 'CN=Liuguang Studio, O=Liuguang, C=CN',
        '-storetype', 'JKS', '-noprompt'
    ], env=env, check=True, capture_output=True)
    properties.write_text(f'storePassword={password}\nkeyPassword={password}\nkeyAlias=liuguang\nstoreFile=../../.signing/liuguang-release.jks\n', encoding='utf-8')
    print('Created private release signing material (ignored by Git).')
