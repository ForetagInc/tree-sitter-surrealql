/**
 * Run all lezer test corpus inputs against both lezer and tree-sitter
 * parsers and check that they produce structurally identical canonical
 * trees. Uses the same normalisation rules as compare.ts.
 *
 *   bun run run-corpus.ts            — runs every test in every dir
 *   bun run run-corpus.ts statements — runs only the given subdir
 */

import { execSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const TS_DIR = path.dirname(fileURLToPath(import.meta.url));
const TS_BIN = path.join(TS_DIR, 'node_modules/.bin/tree-sitter');
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

function fmtFlat(n: CNode): string {
	if (n.children.length === 0) return n.name;
	return `${n.name}(${n.children.map(fmtFlat).join(',')})`;
}

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

function tsCanonical(input: string): CNode | null {
	const tmp = path.join(TS_DIR, '.corpus.tmp.surql');
	fs.writeFileSync(tmp, input);
	let raw: string;
	try {
		raw = execSync(`${TS_BIN} parse ${tmp} 2>/dev/null || true`, {
			encoding: 'utf-8',
		});
	} finally {
		try {
			fs.unlinkSync(tmp);
		} catch {
			/* ignore */
		}
	}
	const s = raw
		.replace(/\[[^\]]*\]/g, '')
		.replace(/[a-zA-Z_][a-zA-Z0-9_]*:/g, '');
	let i = 0;
	function skipWs() {
		while (i < s.length && /\s/.test(s[i] ?? '')) i++;
	}
	function readName(): string {
		const start = i;
		while (i < s.length && /[A-Za-z0-9_]/.test(s[i] ?? '')) i++;
		return s.slice(start, i);
	}
	function parseNode(): CNode | null {
		skipWs();
		if (s[i] !== '(') return null;
		i++;
		skipWs();
		const name = readName();
		if (!name) return null;
		const node: CNode = { name, children: [] };
		while (true) {
			skipWs();
			if (s[i] === ')') {
				i++;
				if (
					node.children.length === 0 &&
					STRIP_WHEN_EMPTY.has(node.name)
				)
					return null;
				if (STRIP_ALWAYS.has(node.name)) return null;
				return node;
			}
			if (s[i] === '(') {
				const child = parseNode();
				if (child) node.children.push(child);
				continue;
			}
			while (i < s.length && !/\s|[()]/.test(s[i] ?? '')) i++;
		}
	}
	return parseNode();
}

function equal(a: CNode | null, b: CNode | null): boolean {
	if (!a && !b) return true;
	if (!a || !b) return false;
	if (a.name !== b.name) return false;
	if (a.children.length !== b.children.length) return false;
	for (let i = 0; i < a.children.length; i++) {
		if (!equal(a.children[i] ?? null, b.children[i] ?? null)) return false;
	}
	return true;
}

interface Result {
	dir: string;
	file: string;
	name: string;
	input: string;
	pass: boolean;
	lezer?: string;
	ts?: string;
}

const target = process.argv[2];
const dirs = target
	? [target]
	: fs
			.readdirSync(LEZER_CORPUS)
			.filter((d) =>
				fs.statSync(path.join(LEZER_CORPUS, d)).isDirectory(),
			);

const results: Result[] = [];

for (const dir of dirs) {
	const dirPath = path.join(LEZER_CORPUS, dir);
	if (!fs.existsSync(dirPath)) continue;
	const files = fs
		.readdirSync(dirPath)
		.filter((f) => f.endsWith('.txt'))
		.sort();
	for (const file of files) {
		const content = fs.readFileSync(path.join(dirPath, file), 'utf-8');
		const tests = content.split(/^# /m).slice(1);
		for (const test of tests) {
			const lines = test.split('\n');
			const name = lines[0].trim();
			const sepIdx = lines.findIndex((l) => l.trim() === '==>');
			if (sepIdx === -1) continue;
			const input = lines.slice(1, sepIdx).join('\n').trim();
			if (!input) continue;
			const lezerTree = lezerCanonical(input);
			const tsTree = tsCanonical(input);
			const pass = equal(lezerTree, tsTree);
			results.push({
				dir,
				file,
				name,
				input,
				pass,
				lezer: lezerTree ? fmtFlat(lezerTree) : '<null>',
				ts: tsTree ? fmtFlat(tsTree) : '<null>',
			});
		}
	}
}

const passed = results.filter((r) => r.pass).length;
const failed = results.length - passed;

console.log(`PASS ${passed}/${results.length}`);
if (failed > 0) {
	console.log('');
	const showFirst = Number.parseInt(process.env.SHOW ?? '10', 10);
	let shown = 0;
	for (const r of results) {
		if (r.pass) continue;
		if (shown >= showFirst) break;
		shown++;
		console.log(`FAIL ${r.dir}/${r.file} :: ${r.name}`);
		console.log(`  input : ${JSON.stringify(r.input).slice(0, 150)}`);
		console.log(`  lezer : ${r.lezer?.slice(0, 250)}`);
		console.log(`  ts    : ${r.ts?.slice(0, 250)}`);
		console.log('');
	}
	if (failed > shown) console.log(`...and ${failed - shown} more failures.`);
	process.exit(1);
}
