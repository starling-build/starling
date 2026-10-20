#!/usr/bin/env python3
"""Publication update and rebuild regressions; uses the native OfficeApp CLI."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parent.parent
APP = Path(os.environ.get('OFFICE_APP', ROOT / 'apps/OfficeApp/.build/debug/OfficeApp')).resolve()
STAGE = Path(os.environ.get('STAGE', ROOT / '.stage-web-OfficeApp')).resolve()


class PublishingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='starling-publishing-')
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        (self.repo / 'pages').mkdir(parents=True)
        self.config = {'title': 'Publication', 'pages': [
            {'slug': 'index', 'title': 'Home'}, {'slug': 'manual', 'title': 'Manual'}]}
        self.write_config()
        self.source = json.loads((ROOT / 'examples/site/pages/about.json').read_text())
        for slug in ('index', 'manual'):
            (self.repo / 'pages' / (slug + '.json')).write_text(json.dumps(self.source))
        self.out = self.repo / 'docs'

    def tearDown(self):
        self.temp.cleanup()

    def write_config(self):
        (self.repo / 'site.json').write_text(json.dumps(self.config))

    def run_app(self, *args, ok=True):
        result = subprocess.run([str(APP), *map(str, args)], text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0 if ok else 1, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def build(self, ok=True, **kwargs):
        return self.run_app('--site-build', self.repo, '--web', kwargs.get('stage', STAGE),
                            '--out', kwargs.get('out', self.out), ok=ok)

    def digest(self):
        return {str(p.relative_to(self.out)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.out.rglob('*') if p.is_file()}

    def test_new_publication_builds_without_handwritten_configuration(self):
        self.run_app('--site-create', self.root, 'New handbook')
        created = self.root / 'new-handbook'
        self.run_app('--site-build', created, '--web', STAGE)
        manifest = json.loads((created / 'docs/manifest.json').read_text())
        self.assertEqual(manifest['title'], 'New handbook')
        self.assertEqual(manifest['home'], 'welcome')
        self.assertIn('New handbook', (created / 'docs/index.html').read_text())
        self.assertTrue((created / 'docs/welcome/welcome.pdf').exists())
        self.assertTrue((created / 'docs/welcome/welcome.docx').exists())
        self.assertFalse((created / 'docs/PUBLISHING.md').exists())

    def test_start_from_word_builds_manuscript_as_home(self):
        source = self.root / 'manuscript.docx'
        self.run_app('--page-docx', self.repo / 'pages/index.json', source)
        original = source.read_bytes()
        self.run_app('--site-create', self.root, 'Writer publication', '--from', source)
        created = self.root / 'writer-publication'
        config = json.loads((created / 'site.json').read_text())
        self.assertEqual(len(config['pages']), 1)
        self.run_app('--site-build', created, '--web', STAGE)
        rendered = json.loads((created / 'docs/pages/welcome.json').read_text())
        self.assertEqual(rendered['document']['paragraphs'][0]['text'], self.source['document']['paragraphs'][0]['text'])
        self.assertIn(self.source['document']['paragraphs'][0]['text'], (created / 'docs/index.html').read_text())
        self.assertEqual(source.read_bytes(), original)

    def test_deleted_page_leaves_no_public_artifacts(self):
        self.build()
        (self.out / 'CNAME').write_text('publications.example.org\n')
        self.config['pages'].pop()
        self.write_config()
        (self.repo / 'pages/manual.json').unlink()
        self.build()
        self.assertFalse((self.out / 'manual').exists())
        self.assertFalse((self.out / 'pages/manual.json').exists())
        self.assertNotIn('manual', (self.out / 'search.json').read_text())
        self.assertEqual((self.out / 'CNAME').read_text(), 'publications.example.org\n')

    def test_home_stays_fixed_when_contents_are_reordered(self):
        self.build()
        self.run_app('--site-move', self.repo, 'index', 'down')
        saved = json.loads((self.repo / 'site.json').read_text())
        self.assertEqual(saved['home'], 'index')
        self.assertEqual(saved['pages'][0]['slug'], 'manual')
        self.build()
        manifest = json.loads((self.out / 'manifest.json').read_text())
        self.assertEqual(manifest['home'], 'index')
        self.assertIn('og:title" content="Home"', (self.out / 'index.html').read_text())
        saved['home'] = 'manual'
        (self.repo / 'site.json').write_text(json.dumps(saved))
        self.build()
        self.assertEqual(json.loads((self.out / 'manifest.json').read_text())['home'], 'manual')
        self.assertIn('og:title" content="Manual"', (self.out / 'index.html').read_text())
        # Both slug aliases still exist, including the old home's direct link.
        for slug in ['index', 'manual']:
            self.assertTrue((self.out / slug / 'index.html').exists())
        self.assertEqual(json.loads((self.out / 'pages/index.json').read_text()), self.source)

    def test_missing_explicit_home_preserves_previous_build(self):
        self.build()
        before = self.digest()
        self.config['home'] = 'absent'
        self.write_config()
        self.build(ok=False)
        self.assertEqual(self.digest(), before)

    def test_failed_build_preserves_every_previous_file(self):
        self.build()
        before = self.digest()
        (self.repo / 'pages/manual.json').write_text('broken JSON')
        self.build(ok=False)
        self.assertEqual(self.digest(), before)
        self.assertFalse(list(self.repo.glob('.starling-build-*')))

    def test_asset_failure_preserves_previous_build(self):
        self.build()
        before = self.digest()
        bad_stage = self.root / 'bad-web'
        bad_stage.mkdir()
        (bad_stage / 'app.wasm').write_bytes(b'placeholder')
        (bad_stage / 'index.html').mkdir()  # fails while reading the template in staging
        self.build(stage=bad_stage, ok=False)
        self.assertEqual(self.digest(), before)
        self.assertFalse(list(self.repo.glob('.starling-build-*')))

    def test_missing_page_is_an_error_not_blank_publication(self):
        (self.repo / 'pages/manual.json').unlink()
        self.assertIn('missing', self.build(ok=False))
        self.assertFalse(self.out.exists())

    def test_invalid_and_duplicate_routes_are_rejected(self):
        for slug in ('../escape', 'fonts', 'pages', 'INDEX'):
            with self.subTest(slug=slug):
                self.config['pages'][1]['slug'] = slug
                self.write_config()
                self.build(ok=False)
                self.assertFalse(self.out.exists())

    def test_source_and_web_cannot_be_output(self):
        for path in (self.repo, self.repo / 'pages', self.repo / '.git', STAGE):
            with self.subTest(path=path):
                self.build(out=path, ok=False)
        self.assertTrue((self.repo / 'pages/manual.json').is_file())

    def test_word_update_preview_apply_and_second_build(self):
        self.build()
        before_config = (self.repo / 'site.json').read_bytes()
        before_source = (self.repo / 'pages/manual.json').read_bytes()
        revised = json.loads(before_source)
        paragraph = revised['document']['paragraphs'][0]
        old_id = paragraph['id']
        paragraph['text'] = 'Revised publication heading'
        paragraph['runs'] = [{'length': len(paragraph['text']), 'style': {}}]
        input_json = self.root / 'revision.json'
        input_json.write_text(json.dumps(revised))
        word = self.root / 'revision.docx'
        self.run_app('--page-docx', input_json, word)
        preview = self.run_app('--site-update', self.repo, 'manual', word)
        self.assertIn('Preview only', preview)
        self.assertEqual((self.repo / 'pages/manual.json').read_bytes(), before_source)
        self.run_app('--site-update', self.repo, 'manual', word, '--apply')
        self.assertEqual((self.repo / 'site.json').read_bytes(), before_config)
        saved = json.loads((self.repo / 'pages/manual.json').read_text())
        self.assertEqual(saved['document']['paragraphs'][0]['id'], old_id)
        self.assertEqual(saved['document']['paragraphs'][0]['text'], paragraph['text'])
        self.build()
        self.assertIn(paragraph['text'], (self.out / 'manual/index.html').read_text())
        self.assertTrue((self.out / 'manual/manual.pdf').is_file())
        self.assertTrue((self.out / 'manual/manual.docx').is_file())
        self.run_app('--site-update', self.repo, 'absent', word, '--apply', ok=False)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True).strip()

    def setup_remote(self):
        remote = self.root / 'remote.git'
        subprocess.run(['git', 'init', '--bare', '-q', str(remote)], check=True)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Publication test')
        self.git('config', 'user.email', 'publication@example.test')
        self.git('add', 'site.json', 'pages')
        self.git('commit', '-qm', 'Initial source')
        self.git('remote', 'add', 'origin', str(remote))
        self.git('push', '-qu', 'origin', 'HEAD')
        return remote

    def state(self):
        return self.run_app('--site-status', self.repo).split(':', 1)[0]

    def test_saved_changes_status_survives_failed_push_and_retry(self):
        remote = self.setup_remote()
        self.assertEqual(self.state(), 'unknown')  # Even a manually pushed clean tree.
        self.run_app('--site-publish', self.repo, '--web', STAGE)
        self.assertEqual(self.state(), 'sent')
        receipt = self.repo / '.git/starling-publish.json'
        before = receipt.read_bytes()
        self.config['title'] = 'Revised publication'
        self.write_config()
        self.assertEqual(self.state(), 'pending')
        self.git('add', 'site.json')
        self.git('commit', '-qm', 'Save revision locally')
        self.assertEqual(self.state(), 'pending')  # Clean tree is still not sent.
        hook = remote / 'hooks/pre-receive'
        hook.write_text('#!/bin/sh\nexit 1\n')
        hook.chmod(0o755)
        self.run_app('--site-publish', self.repo, '--web', STAGE, ok=False)
        self.assertEqual(receipt.read_bytes(), before)
        self.assertEqual(self.state(), 'pending')
        hook.unlink()
        self.run_app('--site-publish', self.repo, '--web', STAGE)
        self.assertEqual(self.state(), 'sent')
        self.assertEqual(json.loads(receipt.read_text())['revision'], self.git('rev-parse', 'HEAD'))

    def test_status_includes_new_ignored_pages_and_deletions_but_not_private_notes(self):
        self.setup_remote()
        self.run_app('--site-publish', self.repo, '--web', STAGE)
        (self.repo / 'notes.txt').write_text('Private note')
        self.git('add', 'notes.txt')
        self.assertEqual(self.state(), 'sent')
        (self.repo / '.gitignore').write_text('pages/new.json\n')
        page = self.repo / 'pages/new.json'
        page.write_text(json.dumps(self.source))
        self.assertEqual(self.state(), 'pending')
        page.unlink()
        (self.repo / 'pages/manual.json').unlink()
        self.assertEqual(self.state(), 'pending')
        self.git('restore', 'pages/manual.json')
        self.assertEqual(self.state(), 'sent')
        self.assertEqual(self.git('diff', '--cached', '--name-only'), 'notes.txt')

    def test_public_build_marker_tracks_uploaded_commit_not_failed_retry(self):
        remote = self.setup_remote()
        self.run_app('--site-publish', self.repo, '--web', STAGE)
        path = 'docs/starling-publication.json'
        marker = json.loads((self.repo / path).read_text())
        self.assertEqual(marker['version'], 1)
        uuid.UUID(marker['build'])
        receipt_file = self.repo / '.git/starling-publish.json'
        receipt = json.loads(receipt_file.read_text())
        uploaded = json.loads(subprocess.check_output(
            ['git', '--git-dir', str(remote), 'show', receipt['revision'] + ':' + path], text=True))
        self.assertEqual(uploaded, marker)
        hook = remote / 'hooks/pre-receive'
        hook.write_text('#!/bin/sh\nexit 1\n')
        hook.chmod(0o755)
        self.run_app('--site-publish', self.repo, '--web', STAGE, ok=False)
        self.assertNotEqual(json.loads((self.repo / path).read_text()), marker)
        self.assertEqual(json.loads(receipt_file.read_text()), receipt)
        self.assertEqual(json.loads(self.git('show', receipt['revision'] + ':' + path)), marker)

    def test_status_does_not_follow_changed_destination_or_corrupt_receipt(self):
        remote = self.setup_remote()
        self.run_app('--site-publish', self.repo, '--web', STAGE)
        receipt = self.repo / '.git/starling-publish.json'
        before = receipt.read_bytes()
        self.git('remote', 'set-url', 'origin', str(self.root / 'other.git'))
        self.assertEqual(self.state(), 'unknown')
        self.git('remote', 'set-url', 'origin', str(remote))
        branch = self.git('branch', '--show-current')
        target = self.git('config', 'branch.' + branch + '.merge')
        self.git('config', 'branch.' + branch + '.merge', 'refs/heads/another')
        self.assertEqual(self.state(), 'unknown')
        self.git('config', 'branch.' + branch + '.merge', target)
        self.assertTrue(self.run_app('--site-status', self.repo, '--out', 'other').startswith('unknown:'))
        self.assertTrue(self.run_app('--site-status', self.repo / 'pages').startswith('unknown:'))
        receipt.write_text('broken')
        self.assertEqual(self.state(), 'unknown')
        receipt.write_bytes(before)
        self.assertEqual(self.state(), 'sent')
        clone = self.root / 'clone'
        subprocess.run(['git', 'clone', '-q', str(remote), str(clone)], check=True)
        self.assertTrue(self.run_app('--site-status', clone).startswith('unknown:'))
        self.assertNotIn('starling-publish.json', self.git('ls-tree', '-r', '--name-only', 'HEAD'))
        # Publishing to an intentionally different branch retains that choice.
        self.git('config', 'branch.' + branch + '.merge', 'refs/heads/publication')
        self.run_app('--site-publish', self.repo, '--web', STAGE)
        self.assertEqual(self.git('rev-parse', '--abbrev-ref', '@{upstream}'), 'origin/publication')
        self.assertEqual(json.loads(receipt.read_text())['target'], 'refs/heads/publication')
        self.assertEqual(self.state(), 'sent')

    def test_receipt_tracks_pinned_upload_if_local_head_changes_during_push(self):
        remote = self.setup_remote()
        hook = self.repo / '.git/hooks/pre-push'
        hook.write_text('#!/bin/sh\ngit -c core.hooksPath=/dev/null commit --allow-empty -qm "Concurrent local commit"\n')
        hook.chmod(0o755)
        self.run_app('--site-publish', self.repo, '--web', STAGE)
        receipt = json.loads((self.repo / '.git/starling-publish.json').read_text())
        uploaded = subprocess.check_output(['git', '--git-dir', str(remote), 'rev-parse', receipt['target']], text=True).strip()
        self.assertEqual(receipt['revision'], uploaded)
        self.assertNotEqual(receipt['revision'], self.git('rev-parse', 'HEAD'))
        self.assertEqual(self.state(), 'sent')  # Extra empty commit changes no publication files.

    def test_publish_preserves_unrelated_staged_and_unstaged_changes(self):
        self.setup_remote()
        (self.repo / 'private-notes.txt').write_text('not publication content')
        (self.repo / 'scratch.txt').write_text('also unrelated')
        self.git('add', 'private-notes.txt')
        result = self.run_app('--site-publish', self.repo, '--web', STAGE)
        self.assertIn('deployment has not been verified', result)
        self.assertNotIn('private-notes.txt', self.git('ls-tree', '-r', '--name-only', 'HEAD'))
        self.assertNotIn('scratch.txt', self.git('ls-tree', '-r', '--name-only', 'HEAD'))
        self.assertEqual(self.git('diff', '--cached', '--name-only'), 'private-notes.txt')
        self.assertTrue((self.repo / 'scratch.txt').exists())
        # A no-change retry must not pick up the unrelated staged file either.
        self.run_app('--site-publish', self.repo, '--web', STAGE)
        self.assertEqual(self.git('diff', '--cached', '--name-only'), 'private-notes.txt')

    def test_first_publish_sets_upstream_without_extra_commands(self):
        self.run_app('--site-create', self.root, 'First publication')
        self.repo = self.root / 'first-publication'
        remote = self.root / 'first-remote.git'
        subprocess.run(['git', 'init', '--bare', '-q', str(remote)], check=True)
        self.git('config', 'user.name', 'Publication test')
        self.git('config', 'user.email', 'publication@example.test')
        self.git('remote', 'add', 'origin', str(remote))
        self.run_app('--site-publish', self.repo, '--web', STAGE)
        self.assertEqual(self.git('rev-parse', '@{upstream}'), self.git('rev-parse', 'HEAD'))
        self.assertEqual(self.git('config', 'branch.main.remote'), 'origin')
        self.assertIn('docs/index.html', self.git('ls-tree', '-r', '--name-only', 'HEAD'))

    def test_incomplete_setup_does_not_build_or_commit(self):
        self.git('init', '-q')
        result = self.run_app('--site-publish', self.repo, '--web', STAGE, ok=False)
        self.assertIn('origin', result)
        self.assertFalse(self.out.exists())
        self.assertEqual(self.git('diff', '--cached', '--name-only'), '')
        self.assertNotEqual(subprocess.run(['git', '-C', str(self.repo), 'rev-parse', '--verify', 'HEAD'], capture_output=True).returncode, 0)

    def test_push_defaults_cannot_redirect_publication(self):
        self.setup_remote()
        other = self.root / 'other.git'
        subprocess.run(['git', 'init', '--bare', '-q', str(other)], check=True)
        self.git('remote', 'add', 'other', str(other))
        self.git('config', 'remote.pushDefault', 'other')
        self.git('config', 'remote.origin.push', 'HEAD:refs/heads/unrelated')
        self.run_app('--site-publish', self.repo, '--web', STAGE)
        self.assertEqual(self.git('rev-parse', '@{upstream}'), self.git('rev-parse', 'HEAD'))
        refs = subprocess.check_output(['git', '--git-dir', str(other), 'for-each-ref'], text=True)
        self.assertEqual(refs, '')
        self.assertNotEqual(subprocess.run(['git', '--git-dir', str(self.root / 'remote.git'), 'rev-parse', '--verify', 'refs/heads/unrelated'], capture_output=True).returncode, 0)

    def test_remote_changes_get_guidance_without_overwriting_either_history(self):
        remote = self.setup_remote()
        self.run_app('--site-publish', self.repo, '--web', STAGE)
        receipt_file = self.repo / '.git/starling-publish.json'
        receipt = receipt_file.read_bytes()
        branch = self.git('branch', '--show-current')
        other = self.root / 'other-author'
        subprocess.run(['git', 'clone', '-q', '-b', branch, str(remote), str(other)], check=True)
        def other_git(*args):
            return subprocess.check_output(['git', '-C', str(other), *args], text=True).strip()
        other_git('config', 'user.name', 'Other author')
        other_git('config', 'user.email', 'other@example.test')
        (other / 'other-author.txt').write_text('Remote work to retain')
        other_git('add', '.')
        other_git('commit', '-qm', 'Other author update')
        other_git('push', '-q', 'origin', branch)
        remote_revision = other_git('rev-parse', 'HEAD')
        self.config['title'] = 'Local writing to retain'
        self.write_config()
        result = self.run_app('--site-publish', self.repo, '--web', STAGE, ok=False)
        self.assertIn('online publication has other changes', result)
        self.assertIn('Review and merge', result)
        self.assertEqual(receipt_file.read_bytes(), receipt)
        self.assertEqual(json.loads((self.repo / 'site.json').read_text())['title'], 'Local writing to retain')
        self.assertEqual(subprocess.check_output(['git', '--git-dir', str(remote), 'rev-parse', branch], text=True).strip(), remote_revision)
        self.assertEqual(self.state(), 'pending')

    def test_rejected_upload_does_not_echo_server_credentials(self):
        remote = self.setup_remote()
        hook = remote / 'hooks/pre-receive'
        hook.write_text('#!/bin/sh\nprintf "secret-token=https://person:password@host/private\\n" >&2\nexit 1\n')
        hook.chmod(0o755)
        result = self.run_app('--site-publish', self.repo, '--web', STAGE, ok=False)
        self.assertIn('Hosting rejected this update', result)
        self.assertIn('local publication history', result)
        self.assertNotIn('secret-token', result)
        self.assertNotIn('password', result)
        self.assertFalse((self.repo / '.git/starling-publish.json').exists())

    def test_retry_after_rejected_push_keeps_local_publication(self):
        remote = self.setup_remote()
        hook = remote / 'hooks/pre-receive'
        hook.write_text('#!/bin/sh\nexit 1\n')
        hook.chmod(0o755)
        self.run_app('--site-publish', self.repo, '--web', STAGE, ok=False)
        self.assertEqual(self.state(), 'unknown')
        self.assertFalse((self.repo / '.git/starling-publish.json').exists())
        committed = self.git('rev-parse', 'HEAD')
        self.assertIn('docs/manifest.json', self.git('ls-tree', '-r', '--name-only', 'HEAD'))
        hook.unlink()
        self.run_app('--site-publish', self.repo, '--web', STAGE)
        # Export metadata can change on regeneration; a retry may add a commit,
        # but it must retain the committed publication and push the new head.
        self.git('merge-base', '--is-ancestor', committed, 'HEAD')
        self.assertEqual(self.git('rev-parse', '@{upstream}'), self.git('rev-parse', 'HEAD'))


if __name__ == '__main__':
    if not APP.is_file() or not (STAGE / 'app.wasm').is_file():
        print('Publishing tests need OfficeApp and its web stage', file=sys.stderr)
        sys.exit(2)
    unittest.main(verbosity=2)
