// Runs the real handler with local fixtures; no OpenAI charges or customer data.
// node --test supabase/functions/vault_ai_chat/handler_test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import { resolveRelationshipFromGraph } from "./relationship_graph.ts";
import * as grounding from "./conversation_grounding.ts";
import { hasAiProcessingConsent } from "../_shared/ai_processing_consent.ts";
import {
  boundedEmbeddingCandidates,
  MAX_QUESTION_CHARACTERS,
} from "../_shared/ai_cost_limits.ts";

import {budgetedJson,AiBudgetError} from "../_shared/ai_budget.ts";

globalThis.Deno = { test };
await import("./conversation_grounding_test.ts");
await import("./relationship_graph_test.ts");

const code = stripTypeScriptTypes(
  readFileSync(new URL("./index.ts", import.meta.url), "utf8").replace(
    /^import .*;\n/gm,
    "",
  ),
);
function fixture(options = {}) {
  const calls = [], queries = [], usage = [];
  let handler, clientOptions;
  const result = (data) => ({ data, error: null });
  const db = {
    auth: {
      getUser: async () =>
        options.signedOut
          ? { error: { message: "signed out" } }
          : result({ user: { id: "viewer" } }),
    },
    rpc: async (name, params) => {
      if (name === "has_ai_processing_consent") {
        return result(options.consent !== false);
      }
      if(name==='reserve_ai_budget')return result(options.budgetDenied?null:'test-reservation');
      if(name==='settle_ai_budget')return result(null);
      assert.equal(name, "everroot_consume_ai_usage");
      usage.push(params);
      return options.quota
        ? { error: { message: "ERR_EVERROOT_AI_LIMIT" } }
        : result(null);
    },
    from(table) {
      const filters = {};
      let selected = "";
      const query = {
        select(s) {
          selected = s;
          return this;
        },
        eq(k, v) {
          filters[k] = v;
          return this;
        },
        in() {
          return this;
        },
        order() {
          return this;
        },
        limit() {
          return this;
        },
        maybeSingle() {
          return this;
        },
        then(resolve, reject) {
          queries.push({ table, filters, selected });
          let value;
          if (table === "legacy_family_members") {
            value = options.denied ? null : {
              id: "Bremner",
              family_id: "family",
              name: "Bremner",
              about_me_text: options.about ?? "Bremner worked on a farm.",
              slot_key: "grandparent_left",
            };
          } else if (table === "vaults") {
            value = filters.owner_id ? { id: "viewer-vault" } : {
              id: "target",
              owner_id: options.self ? "viewer" : "owner",
              family_id: "family",
              name: "Jenna",
            };
          } else if (table === "family_members") {
            value = options.wrongFamily
              ? []
              : [{ user_id: "viewer" }, { user_id: "owner" }];
          } else if (
            table === "family_relationships"
          ) {
            value = options.graph ?? [
              {
                parent_type: "legacy",
                parent_id: "Bremner",
                child_type: "vault",
                child_id: "P",
                relationship_kind: "parent_child",
              },
              {
                parent_type: "vault",
                parent_id: "P",
                child_type: "vault",
                child_id: "Q",
                relationship_kind: "parent_child",
              },
              {
                parent_type: "vault",
                parent_id: "Q",
                child_type: "vault",
                child_id: "viewer-vault",
                relationship_kind: "parent_child",
              },
            ];
          } else if (table === "memory_chunks") {
            value = [{
              chunk_text: "Jenna is an IP student.",
            }];
          } else if (
            ["legacy_memories", "legacy_memory_voice_notes"].includes(table)
          ) value = [];
          else throw Error(`Unexpected table ${table}`);
          return Promise.resolve(
            table === "family_relationships" && options.graphError
              ? { error: { message: "unavailable" }, data: null }
              : result(value),
          ).then(resolve, reject);
        },
      };
      return query;
    },
  };
  const bindings = {
    serve: (fn) => handler = fn,
    createClient: (_url, _key, opts) => {
      if(opts?.global?.headers?.Authorization) clientOptions = opts;
      return db;
    },
    Deno: { env: { get: () => "fixture-only" } },
    resolveRelationshipFromGraph,
    ...grounding,
    hasAiProcessingConsent,
    budgetedJson, AiBudgetError,
    boundedEmbeddingCandidates,
    MAX_QUESTION_CHARACTERS,
    fetch: async (url, init) => {
      assert.equal(url, "https://api.openai.com/v1/chat/completions");
      calls.push(JSON.parse(init.body));
      return Response.json({
        choices: [{ message: { content: "Saved-source fixture answer." } }],
      });
    },
  };
  new Function(...Object.keys(bindings), code)(...Object.values(bindings));
  return {
    calls,
    queries,
    usage,
    get clientOptions() {
      return clientOptions;
    },
    async ask(question, extra = {}) {
      const response = await handler(
        new Request("https://local.test", {
          method: "POST",
          headers: {
            Authorization: "Bearer fixture-jwt",
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            legacyMemberId: "Bremner",
            familyId: "family",
            question,
            ...extra,
          }),
        }),
      );
      return { status: response.status, body: await response.json() };
    },
  };
}
test("exact Bremner story question reaches grounded completion once, not the kinship shortcut", async () => {
  const f = fixture();
  const q = "Can you share a favorite memory you have of your grandparents?";
  const r = await f.ask(q);
  assert.equal(r.body.answer, "Saved-source fixture answer.");
  assert.equal(f.calls.length, 1);
  assert.equal(f.usage.length, 1);
  const c = f.calls[0];
  assert.equal(c.model, "gpt-4o-mini");
  assert.equal(c.max_tokens, 220);
  assert.ok(c.messages[1].content.includes(q));
  assert.ok(c.messages[1].content.includes('"grandparents":0'));
  assert.ok(c.messages[1].content.includes('"grandparents":1'));
  assert.ok(c.messages[0].content.includes("asks about the PROFILE"));
  assert.equal(
    f.clientOptions.global.headers.Authorization,
    "Bearer fixture-jwt",
  );
});
test("explicit relationship still returns correct great-grandparent without paid model call", async () => {
  const f = fixture();
  const r = await f.ask("How are we related?");
  assert.equal(
    r.body.answer,
    "I am your great-grandparent. You are my great-grandchild.",
  );
  assert.equal(f.calls.length, 0);
  assert.equal(f.usage.length, 0);
});
test("empty profile answers missing grandparents specifically, for free", async () => {
  const f = fixture({ about: "" });
  const r = await f.ask("Tell me a memory of your grandparents");
  assert.match(r.body.answer, /No grandparents are linked to my profile/);
  assert.equal(f.calls.length, 0);
  assert.equal(f.usage.length, 0);
});
test("saved story about unlinked grandmother is still supplied to the model", async () => {
  const f = fixture({
    about: "My grandmother taught me to bake bread.",
    graph: [],
  });
  await f.ask("Tell me about your grandparents");
  assert.ok(f.calls[0].messages[1].content.includes("taught me to bake bread"));
  assert.ok(f.calls[0].messages[1].content.includes("saved story can still"));
});
test("slots cannot invent kinship; failed graph remains unknown", async () => {
  for (const opts of [{ graph: [] }, { graphError: true }]) {
    const f = fixture(opts);
    const r = await f.ask("How are we related?");
    assert.match(r.body.answer, /can’t tell your exact relationship/);
    assert.equal(f.calls.length, 0);
  }
});
test("private vault, same-owner vault and normal memory path still use the bounded model", async () => {
  for (const self of [true, false]) {
    const f = fixture({ self });
    const r = await f.ask("What did you study?", {
      legacyMemberId: null,
      vaultId: "target",
    });
    assert.equal(r.status, 200);
    assert.equal(f.calls.length, 1);
    assert.ok(f.calls[0].messages[1].content.includes("IP student"));
  }
});
test("access, consent, membership, quota and question-size guards still stop paid calls", async () => {
  for (
    const [opts, extra, status] of [
      [{ signedOut: true }, {}, 401],
      [{ consent: false }, {}, 403],
      [{ denied: true }, {}, 403],
      [{ wrongFamily: true }, { vaultId: "target", legacyMemberId: null }, 403],
      [{ quota: true }, {}, 429],
      [{}, { question: "x".repeat(2001) }, 400],
    ]
  ) {
    const f = fixture(opts);
    const r = await f.ask("What did you study?", extra);
    assert.equal(r.status, status, JSON.stringify(opts));
    assert.equal(f.calls.length, 0);
  }
});

test('daily AI budget denial makes no paid call and returns a safe explanation',async()=>{
 const f=fixture({budgetDenied:true});const r=await f.ask('Tell me about farming');
 assert.equal(r.status,429);assert.equal(r.body.code,'AI_DAILY_SAFETY_LIMIT');assert.equal(f.calls.length,0);
});
