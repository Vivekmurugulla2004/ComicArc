import os
root = os.path.abspath(os.path.join(SPECPATH, '..'))

a = Analysis(
    [os.path.join(root, 'main.py')],
    pathex=[root],
    binaries=[],
    datas=[
        (os.path.join(root, 'templates'),           'templates'),
        (os.path.join(root, 'static', 'css'),       'static/css'),
        (os.path.join(root, 'static', 'js'),        'static/js'),
        (os.path.join(root, 'static', 'fonts'),     'static/fonts'),
    ],
    hiddenimports=[
        'waitress', 'waitress.runner',
        'webview', 'webview.platforms.cocoa',
        'flask', 'jinja2', 'werkzeug',
        'sqlite3', 'pymupdf', 'rarfile',
    ],
    hookspath=[],
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data)

exe = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name='ComicArc',
    icon=os.path.join(root, 'assets', 'icon.ico'),
    console=False,
)

coll = COLLECT(exe, a.binaries, a.zipfiles, a.datas, name='ComicArc')

app = BUNDLE(
    coll,
    name='ComicArc.app',
    icon=os.path.join(root, 'assets', 'icon.icns'),
    bundle_identifier='com.vivekmurugulla.comicarc',
    info_plist={
        'NSHighResolutionCapable': True,
        'LSMinimumSystemVersion': '11.0',
        'CFBundleShortVersionString': '1.0.0',
    },
)
