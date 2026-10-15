import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { convert, splitEmoji } from "../scripts/mmbak.js";
import { createApp } from "../src/app.js";
import { disk, sqlite } from "../src/node-adapters.js";

// A minimal Money Manager Android backup using the real table/column names (docs/realbyte-analysis.md §1).
function androidBackup() {
  const db = new DatabaseSync(":memory:");
  db.exec(`
    PRAGMA user_version = 19;
    CREATE TABLE ASSETGROUP (DEVICE_ID INTEGER PRIMARY KEY, uid TEXT, ACC_GROUP_NAME TEXT, TYPE INTEGER, ORDERSEQ INTEGER, IS_DEL INTEGER, USETIME INTEGER);
    CREATE TABLE ASSETS (ID INTEGER PRIMARY KEY, uid TEXT, NIC_NAME TEXT, groupUid TEXT, ORDERSEQ INTEGER, ZDATA TEXT, ZDATA1 TEXT, ZDATA2 TEXT);
    CREATE TABLE ZCATEGORY (ID INTEGER PRIMARY KEY, uid TEXT, NAME TEXT, TYPE INTEGER, STATUS INTEGER, pUid TEXT, ORDERSEQ INTEGER, C_IS_DEL INTEGER);
    CREATE TABLE INOUTCOME (AID INTEGER PRIMARY KEY, uid TEXT, assetUid TEXT, toAssetUid TEXT, ctgUid TEXT, DO_TYPE TEXT, ZMONEY TEXT, ZDATE TEXT, WDATE TEXT, ZCONTENT TEXT, ZDATA TEXT, txUidTrans TEXT, IS_DEL INTEGER, UTIME INTEGER);
    CREATE TABLE ZETC (Z_PK INTEGER PRIMARY KEY, ZDATATYPE INTEGER, ZDATA TEXT, isDel INTEGER);
    CREATE TABLE CURRENCY (ID INTEGER PRIMARY KEY, uid TEXT, ISO TEXT, IS_MAIN_CURRENCY INTEGER, IS_DEL INTEGER);
    CREATE TABLE BUDGET (uid TEXT, targetUid TEXT, IS_TOTAL INTEGER, IS_DEL INTEGER);
    CREATE TABLE BUDGET_AMOUNT (uid TEXT, budgetUid TEXT, AMOUNT REAL, BUDGET_PERIOD INTEGER, IS_DEL INTEGER);

    INSERT INTO ASSETGROUP VALUES (1,'11','Cash',11,0,0,0),(2,'1','Accounts',1,1,0,0),(3,'2','Card',2,2,0,0);
    INSERT INTO ASSETS VALUES (1,'11','Wallet','11',0,'0','',''),(2,'1','Checking','1',0,'0','main bank','0'),(3,'2','Visa','2',0,'0','',''),(4,'old','Closed','1',1,'1','','');
    INSERT INTO ZCATEGORY VALUES (1,'2','💰 Salary',0,0,'0',1,0),(2,'6','🍜 Food',1,0,'0',1,0),(3,'18','Lunch',1,2,'6',0,0),(4,'9','🚖 Transport',1,0,'0',2,0),(5,'99','Gone',1,0,'0',3,1);
    INSERT INTO INOUTCOME VALUES
      (1,'t1','1','','2','0','3000.0','1790000000000','2026-09-21','Paycheck','',NULL,0,1790000000000),
      (2,'t2','11','','18','1','12.5','1790100000000','2026-09-22','Burrito','extra guac',NULL,0,0),
      (3,'t3','2','','9','1','40.0','1790200000000','2026-09-23','Uber','',NULL,0,0),
      (4,'t4','1','11','','3','100.0','1790300000000','2026-09-24','ATM','','pair1',0,0),
      (5,'t5','11','1','','4','100.0','1790300000000','2026-09-24','ATM','','pair1',0,0),
      (6,'t6','11','','-4','7','50.0','1789000000000','2026-09-10','','',NULL,0,0),
      (7,'t7','11','','6','1','999.0','1790400000000','2026-09-25','deleted','',NULL,1,0),
      (8,'t8','old','','6','1','5.0','1790400000000','2026-09-25','On closed acct','',NULL,0,0);
    INSERT INTO ZETC VALUES (1,-23459,'25',0),(2,10002,'1',0);
    INSERT INTO CURRENCY VALUES (1,'EUR_EUR','EUR',1,0);
    INSERT INTO BUDGET VALUES ('b1','6',0,0),('b2','',1,0);
    INSERT INTO BUDGET_AMOUNT VALUES ('ba1','b1',200,0,0),('ba2','b1',300,202601,0),('ba3','b2',1000,0,0),('ba4','b1',999,209912,0);
  `);
  return db;
}

test("splitEmoji", () => {
  assert.deepEqual(splitEmoji("🍜 Food"), { icon: "🍜", name: "Food" });
  assert.deepEqual(splitEmoji("👬🏻 Social Life"), { icon: "👬🏻", name: "Social Life" });
  assert.deepEqual(splitEmoji("🧘🏼 Health"), { icon: "🧘🏼", name: "Health" });
  assert.deepEqual(splitEmoji("Other"), { icon: "", name: "Other" });
});

test("converts an Android backup and imports it", async () => {
  const { flavor, data, warnings } = convert(androidBackup(), "America/New_York");
  assert.equal(flavor, "android");
  assert.equal(data.settings?.currency, "EUR");
  assert.equal(data.settings?.month_start_day, "25");
  assert.equal(data.settings?.week_start, "1");
  assert.equal(data.transactions?.length, 5, JSON.stringify(data.transactions?.map((t) => t.id))); // t1,t2,t3,t4 transfer, t8 on closed account
  const lunch = data.categories?.find((c) => c.name === "Lunch");
  assert.equal(lunch?.parent_id, "mm-c-6");
  assert.equal(data.categories?.find((c) => c.name === "Food")?.icon, "🍜");
  assert.equal(data.budgets?.find((b) => b.category_id === "mm-c-6")?.amount, 300);

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mb-import-"));
  const deps = { sql: sqlite(":memory:"), blobs: disk(dir), apiToken: "t" };
  const app = createApp(() => deps);
  const call = async (method: string, url: string, body?: unknown) => {
    const res = await app.request(url, { method, headers: { Authorization: "Bearer t", "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined });
    return { status: res.status, json: await res.json() as any };
  };
  await call("GET", "/api/accounts"); // seed defaults first, then replace them
  const r = await call("POST", "/api/import?replace=1", data);
  assert.equal(r.status, 200, JSON.stringify(r.json));
  // Idempotent re-import.
  assert.equal((await call("POST", "/api/import", { transactions: data.transactions })).status, 200);

  const { json: accounts } = await call("GET", "/api/accounts");
  assert.deepEqual(accounts.map((a: any) => a.name).sort(), ["Checking", "Closed", "Visa", "Wallet"]);
  const { json: bal } = await call("GET", "/api/balances");
  const b = Object.fromEntries(bal.accounts.map((a: any) => [a.name, a.balance]));
  assert.equal(b.Wallet, 50 - 12.5 + 100);
  assert.equal(b.Checking, 3000 - 100);
  assert.equal(b.Visa, -40);
  const { json: tx } = await call("GET", "/api/transactions?q=Burrito");
  assert.equal(tx[0].category_name, "Lunch");
  assert.equal(tx[0].parent_category_name, "Food");
  assert.equal(tx[0].description, "extra guac");
  const { json: cats } = await call("GET", "/api/categories");
  assert.ok(!cats.some((c: any) => c.name === "Pets"), "seeded defaults replaced");
  const { json: settings } = await call("GET", "/api/settings");
  assert.equal(settings.default_account_id, "mm-a-11");
});
