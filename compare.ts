/**
 * Comparison harness: parses a SurrealQL file with both the lezer parser and
 * the tree-sitter parser, normalises both outputs to a canonical
 * `Name(child, …)` S-expression, and diffs them.
 *
 * Usage:  bun run compare [file]    (defaults to ./reference.surql)
 *
 * Exits 0 on match, 1 on mismatch (with first diverging subtree printed).
 */

import { execSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

// ---------------------------------------------------------------------------
// Canonical tree representation
// ---------------------------------------------------------------------------

interface CNode {
	name: string;
	children: CNode[];
	/** byte offset for error reporting only — not used in comparison */
	from?: number;
	to?: number;
}

function fmt(node: CNode, indent = ''): string {
	if (node.children.length === 0) return `${indent}${node.name}`;
	const out = [`${indent}${node.name}(`];
	for (const c of node.children) out.push(fmt(c, `${indent}  `));
	out.push(`${indent})`);
	return out.join('\n');
}

function fmtFlat(node: CNode): string {
	if (node.children.length === 0) return node.name;
	return `${node.name}(${node.children.map(fmtFlat).join(',')})`;
}

// ---------------------------------------------------------------------------
// Lezer side
// ---------------------------------------------------------------------------

const TS_DIR_FOR_LEZER = path.dirname(fileURLToPath(import.meta.url));
const LEZER_DIST_CANDIDATES = [
	path.resolve(
		TS_DIR_FOR_LEZER,
		'../codemirror/packages/lezer-surrealql/dist/index.cjs',
	),
	path.resolve(
		TS_DIR_FOR_LEZER,
		'../../codemirror/packages/lezer-surrealql/dist/index.cjs',
	),
	process.env.LEZER_DIST ?? '',
].filter(Boolean);

const LEZER_DIST =
	LEZER_DIST_CANDIDATES.find((p) => fs.existsSync(p)) ??
	LEZER_DIST_CANDIDATES[0];

// biome-ignore lint/suspicious/noExplicitAny: dynamic CJS interop
async function loadLezer(): Promise<any> {
	if (!fs.existsSync(LEZER_DIST)) {
		throw new Error(
			`Lezer dist not found at ${LEZER_DIST}. Run 'bun run build' in lezer-surrealql.`,
		);
	}
	// biome-ignore lint/suspicious/noExplicitAny: dynamic CJS interop
	const m = (await import(LEZER_DIST)) as any;
	return m.parser ?? m.default?.parser;
}

/**
 * Node names that lezer emits even when their content matched zero tokens.
 * Tree-sitter cannot natively represent these (every rule must consume at
 * least one token). We strip them from the lezer side when they're empty so
 * trees compare cleanly. When they're non-empty (e.g. `EnforcedClause(Keyword)`
 * for explicit `ENFORCED`) they pass through normally.
 */
const STRIP_WHEN_EMPTY = new Set([
	'EnforcedClause',
	'DefaultAlways',
	'ApiOptions',
	'RecurseOptions',
	// Lezer emits a zero-width error placeholder (⚠ → ERROR) where the grammar
	// expected a non-optional element but the input is missing it. Tree-sitter
	// emits no such placeholder, so we drop empty ERRORs to compare structurally.
	'ERROR',
]);

/**
 * Lezer emits single-character punctuation tokens (`[`, `]`, `<`, `>`, raw
 * operator characters) as named nodes in the tree because they are declared
 * (without an @name alias) in the `@tokens` block. Tree-sitter does not emit
 * literal string tokens as named nodes, so we strip these from the lezer side
 * for structural comparison.
 */
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

function lezerToCanonical(
	input: string,
	parser: { parse(s: string): unknown },
): CNode {
	// biome-ignore lint/suspicious/noExplicitAny: lezer tree cursor types are minimal
	const tree = parser.parse(input) as any;
	const cursor = tree.cursor();

	function walk(): CNode {
		// Skip anonymous nodes (they're lezer's inline tokens with no @name)
		const type = cursor.type;
		const name = cursor.name as string;
		const isAnon = type?.isAnonymous as boolean;
		// Normalise lezer's error node name (⚠) to the tree-sitter convention.
		const normName = name === '\u26A0' ? 'ERROR' : name;
		const node: CNode = {
			name: normName,
			children: [],
			from: cursor.from,
			to: cursor.to,
		};

		if (cursor.firstChild()) {
			do {
				const child = walk();
				if (child) node.children.push(child);
			} while (cursor.nextSibling());
			cursor.parent();
		}

		// If this is an anonymous (unnamed) node, drop it but keep its children
		// hoisted up — we'll return its children as a flat structure via the
		// caller's array. Easier: just return null and let caller skip it.
		if (isAnon) return null as unknown as CNode;
		// Strip empty-by-design nodes that tree-sitter cannot reproduce.
		if (node.children.length === 0 && STRIP_WHEN_EMPTY.has(normName)) {
			return null as unknown as CNode;
		}
		// Strip single-character punctuation tokens that lezer keeps as named
		// nodes but tree-sitter emits as anonymous string-literals (omitted).
		if (STRIP_ALWAYS.has(normName)) return null as unknown as CNode;
		return node;
	}

	const root = walk();
	return flattenErrors(root);
}

// Recursively flatten non-empty ERROR nodes by replacing them with their
// children in their parent's children list. Lezer and tree-sitter recover
// from errors differently and wrap different scopes in ERROR; flattening
// gives the surrounding well-formed structure a chance to align.
function flattenErrors(node: CNode | null): CNode | null {
	if (!node) return null;
	const flatChildren: CNode[] = [];
	for (const c of node.children) {
		const f = flattenErrors(c);
		if (!f) continue;
		if (f.name === 'ERROR') flatChildren.push(...f.children);
		else flatChildren.push(f);
	}
	node.children = flatChildren;
	return node;
}

// ---------------------------------------------------------------------------
// Tree-sitter side
// ---------------------------------------------------------------------------

const TS_DIR = path.resolve(fileURLToPath(import.meta.url), '..');
const TS_BIN = path.join(TS_DIR, 'node_modules/.bin/tree-sitter');

function treeSitterSExpr(input: string): string {
	const tmp = path.join(TS_DIR, '.compare.tmp.surql');
	fs.writeFileSync(tmp, input);
	try {
		// tree-sitter parse exits non-zero on parse errors but still emits the
		// (ERROR ...) tree we want to inspect, so we capture stdout regardless.
		return execSync(`${TS_BIN} parse ${tmp} 2>/dev/null || true`, {
			encoding: 'utf-8',
		});
	} finally {
		try {
			fs.unlinkSync(tmp);
		} catch {
			/* ignore */
		}
	}
}

/**
 * Parse tree-sitter's S-expression output into a CNode tree.
 *
 * Tree-sitter outputs e.g.:
 *   (SurrealQL [0, 0] - [10, 0]
 *     (SelectStatement [0, 0] - [0, 19]
 *       (Keyword [0, 0] - [0, 6])
 *       (Fields [0, 7] - [0, 8]
 *         (Any [0, 7] - [0, 8]))))
 *
 * We strip ranges and return only the names + children.
 */
function parseTreeSitterSExpr(raw: string): CNode | null {
	const result = parseTreeSitterSExprInner(raw);
	return flattenErrors(result);
}

function parseTreeSitterSExprInner(raw: string): CNode | null {
	// Strip range annotations `[x, y] - [x, y]` and field labels `name:`
	let s = raw.replace(/\[[^\]]*\]/g, '');
	s = s.replace(/[a-zA-Z_][a-zA-Z0-9_]*:/g, ''); // field labels (rare in our grammar)

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
		i++; // consume '('
		skipWs();
		const name = readName();
		if (!name) return null;
		const node: CNode = { name, children: [] };
		while (true) {
			skipWs();
			if (s[i] === ')') {
				i++;
				// Apply same normalisation rules as the lezer side.
				if (
					node.children.length === 0 &&
					STRIP_WHEN_EMPTY.has(node.name)
				) {
					return null;
				}
				if (STRIP_ALWAYS.has(node.name)) return null;
				return node;
			}
			if (s[i] === '(') {
				const child = parseNode();
				if (child) node.children.push(child);
				continue;
			}
			// Unknown char (anonymous token text) — skip until ws or paren
			while (i < s.length && !/\s|[()]/.test(s[i] ?? '')) i++;
		}
	}
	return parseNode();
}

// ---------------------------------------------------------------------------
// Diff
// ---------------------------------------------------------------------------

interface DiffResult {
	path: string;
	expected: CNode | undefined;
	actual: CNode | undefined;
	expectedTreeFmt: string;
	actualTreeFmt: string;
}

function diffAll(
	expected: CNode | null,
	actual: CNode | null,
	path: string,
	out: DiffResult[],
): void {
	if (!expected && !actual) return;
	if (!expected || !actual) {
		out.push({
			path,
			expected: expected ?? undefined,
			actual: actual ?? undefined,
			expectedTreeFmt: expected ? fmtFlat(expected) : '<missing>',
			actualTreeFmt: actual ? fmtFlat(actual) : '<missing>',
		});
		return;
	}
	if (expected.name !== actual.name) {
		out.push({
			path,
			expected,
			actual,
			expectedTreeFmt: fmtFlat(expected),
			actualTreeFmt: fmtFlat(actual),
		});
		// Don't descend on name mismatch — diff is at this level.
		return;
	}
	const max = Math.max(expected.children.length, actual.children.length);
	for (let k = 0; k < max; k++) {
		const e = expected.children[k];
		const a = actual.children[k];
		diffAll(e ?? null, a ?? null, `${path}.${expected.name}[${k}]`, out);
	}
}

function diff(expected: CNode | null, actual: CNode | null): DiffResult | null {
	const all: DiffResult[] = [];
	diffAll(expected, actual, '$', all);
	return all[0] ?? null;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
	const target = process.argv[2] ?? path.join(TS_DIR, 'reference.surql');
	if (!fs.existsSync(target)) {
		console.error(`File not found: ${target}`);
		process.exit(2);
	}
	const input = fs.readFileSync(target, 'utf-8');

	const parser = await loadLezer();
	const lezerTree = lezerToCanonical(input, parser);
	const tsSExpr = treeSitterSExpr(input);
	const tsTree = parseTreeSitterSExpr(tsSExpr);

	if (process.env.DUMP === '1') {
		console.log('LEZER:');
		console.log(lezerTree ? fmt(lezerTree) : '<null>');
		console.log('');
		console.log('TREE-SITTER:');
		console.log(tsTree ? fmt(tsTree) : '<null>');
		console.log('');
	}

	const all: DiffResult[] = [];
	diffAll(lezerTree, tsTree, '$', all);

	// Top-level statement match summary
	const lezerKids = lezerTree?.children ?? [];
	const tsKids = tsTree?.children ?? [];
	const totalStmts = Math.max(lezerKids.length, tsKids.length);
	let matchedStmts = 0;
	for (let i = 0; i < totalStmts; i++) {
		const lk = lezerKids[i] ?? null;
		const tk = tsKids[i] ?? null;
		const stmtDiffs: DiffResult[] = [];
		diffAll(lk, tk, `$.SurrealQL[${i}]`, stmtDiffs);
		if (stmtDiffs.length === 0) matchedStmts++;
	}

	if (all.length === 0) {
		console.log(`MATCH ✓ ${target} (${countNodes(lezerTree)} named nodes)`);
		return;
	}

	const maxShow = process.env.ALL === '1' ? all.length : 5;
	console.log(
		`MISMATCH: ${all.length} divergence(s); ${matchedStmts}/${totalStmts} top-level statements match. Showing first ${Math.min(maxShow, all.length)}.`,
	);
	for (let i = 0; i < Math.min(maxShow, all.length); i++) {
		const result = all[i];
		console.log(`\n[${i + 1}] at ${result.path}`);
		console.log('  lezer       :', result.expectedTreeFmt.slice(0, 400));
		console.log('  tree-sitter :', result.actualTreeFmt.slice(0, 400));
		if (result.expected?.from !== undefined) {
			const ctx = sliceContext(
				input,
				result.expected.from,
				result.expected.to ?? result.expected.from,
			);
			console.log('  source span :', JSON.stringify(ctx).slice(0, 160));
		}
	}
	process.exit(1);
}

function countNodes(n: CNode | null): number {
	if (!n) return 0;
	let count = 1;
	for (const c of n.children) count += countNodes(c);
	return count;
}

function sliceContext(input: string, from: number, to: number): string {
	const start = Math.max(0, from - 20);
	const end = Math.min(input.length, to + 20);
	return input.slice(start, end);
}

main().catch((err) => {
	console.error(err);
	process.exit(2);
});
