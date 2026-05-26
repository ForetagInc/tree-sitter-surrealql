/**
 * Regenerate `test/corpus/*.txt` from the lezer test inputs and lezer's
 * parser output. For each `<dir>/<file>.txt` in lezer's test corpus, write a
 * matching tree-sitter test fixture using lezer's tree (canonicalised
 * through the same normalisation rules as compare.ts) as the expected output.
 *
 *   bun run gen-corpus.ts
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const TS_DIR = path.dirname(fileURLToPath(import.meta.url));
const CORPUS_OUT = path.join(TS_DIR, 'test', 'corpus');
const LEZER_CORPUS = path.resolve(
	TS_DIR,
	'../codemirror/packages/lezer-surrealql/test',
);
const LEZER_DIST = path.resolve(
	TS_DIR,
	'../codemirror/packages/lezer-surrealql/dist/index.cjs',
);

interface CNode {
	name: string;
	children: CNode[];
}

const STRIP_WHEN_EMPTY = new Set([
	'EnforcedClause',
	'DefaultAlways',
	'ApiOptions',
	'RecurseOptions',
	'ERROR',
]);
const STRIP_ALWAYS = new Set([
	'[',
	']',
	'(',
	')',
	'<',
	'>',
	'+',
	'-',
	'=',
	'*',
	'~',
	'!~',
	'*~',
	'/',
	'%',
	'?',
	'!',
	'@',
	'|>',
	'<|',
]);

// biome-ignore lint/suspicious/noExplicitAny: dynamic CJS interop
const lezerMod: any = await import(LEZER_DIST);
const lezerParser = lezerMod.parser ?? lezerMod.default?.parser;

function lezerCanonical(input: string): CNode | null {
	// biome-ignore lint/suspicious/noExplicitAny: lezer
	const tree = lezerParser.parse(input) as any;
	const cursor = tree.cursor();
	function walk(): CNode | null {
		const name = cursor.name as string;
		const isAnon = cursor.type?.isAnonymous as boolean;
		const normName = name === '\u26A0' ? 'ERROR' : name;
		const node: CNode = { name: normName, children: [] };
		if (cursor.firstChild()) {
			do {
				const child = walk();
				if (child) node.children.push(child);
			} while (cursor.nextSibling());
			cursor.parent();
		}
		if (isAnon) return null;
		if (node.children.length === 0 && STRIP_WHEN_EMPTY.has(normName))
			return null;
		if (STRIP_ALWAYS.has(normName)) return null;
		return node;
	}
	return walk();
}

function formatTree(node: CNode, indent = ''): string {
	if (node.children.length === 0) return `${indent}(${node.name})`;
	const out = [`${indent}(${node.name}`];
	for (let i = 0; i < node.children.length; i++) {
		out.push(formatTree(node.children[i], `${indent}  `));
	}
	out[out.length - 1] += ')';
	return out.join('\n');
}

function makeFixture(name: string, input: string, tree: CNode): string {
	const header = '='.repeat(name.length);
	return `${header}\n${name}\n${header}\n\n${input}\n\n---\n\n${formatTree(tree)}\n`;
}

const dirs = fs
	.readdirSync(LEZER_CORPUS)
	.filter((d) => fs.statSync(path.join(LEZER_CORPUS, d)).isDirectory());

fs.mkdirSync(CORPUS_OUT, { recursive: true });
let totalTests = 0;

for (const dir of dirs) {
	const lezerDir = path.join(LEZER_CORPUS, dir);
	const files = fs
		.readdirSync(lezerDir)
		.filter((f) => f.endsWith('.txt'))
		.sort();

	const fixtures: string[] = [];
	for (const file of files) {
		const content = fs.readFileSync(path.join(lezerDir, file), 'utf-8');
		const tests = content.split(/^# /m).slice(1);
		for (const test of tests) {
			const lines = test.split('\n');
			const name = lines[0].trim();
			const sepIdx = lines.findIndex((l) => l.trim() === '==>');
			if (sepIdx === -1) continue;
			const input = lines.slice(1, sepIdx).join('\n').trim();
			if (!input) continue;
			const tree = lezerCanonical(input);
			if (!tree) continue;
			const qualifiedName = `${file.replace(/\.txt$/, '')} :: ${name}`;
			fixtures.push(makeFixture(qualifiedName, input, tree));
			totalTests++;
		}
	}

	const outPath = path.join(CORPUS_OUT, `${dir}.txt`);
	fs.writeFileSync(outPath, fixtures.join('\n'));
	console.log(
		`Wrote ${fixtures.length} fixtures to ${path.relative(TS_DIR, outPath)}`,
	);
}

console.log(`\nTotal: ${totalTests} test fixtures.`);
