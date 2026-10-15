// Generated from server/scripts/mmbak.ts by npm run build:web. Do not edit.

// scripts/mmbak.ts
var GROUP_TYPES = {
  11: "Cash",
  1: "Accounts",
  2: "Card",
  3: "Debit Card",
  4: "Savings",
  6: "Top-Up/Prepaid",
  8: "Investments",
  9: "Overdrafts",
  5: "Loan",
  10: "Insurance",
  7: "Others"
};
var groupKind = (type) => type === 2 ? "card" : type === 5 || type === 9 ? "liability" : "asset";
var isDeleted = (v) => String(v ?? "0") === "1";
var num = (v) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
function tableNames(db) {
  return new Set(db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map((r) => r.name));
}
function columns(db, table) {
  return new Set(db.prepare(`PRAGMA table_info("${table}")`).all().map((r) => r.name));
}
function rows(db, table) {
  return db.prepare(`SELECT * FROM "${table}"`).all();
}
function pick(cols, ...candidates) {
  return candidates.find((c) => cols.has(c));
}
function splitEmoji(raw) {
  const m = raw.trim().match(/^((?:\p{Extended_Pictographic}|\p{Regional_Indicator})(?:[\u{FE0F}\u{200D}\p{Emoji_Modifier}\p{Extended_Pictographic}\p{Regional_Indicator}])*)\s*(.*)$/u);
  return m && m[2] ? { icon: m[1], name: m[2].trim() } : { icon: "", name: raw.trim() };
}
function localDateTime(ms, timezone) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", { timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(new Date(ms)).map((p) => [p.type, p.value])
  );
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`;
}
function currentPeriod() {
  const d = /* @__PURE__ */ new Date();
  return d.getFullYear() * 100 + d.getMonth() + 1;
}
function effectiveBudgets(budgets, amounts, f, a) {
  const now = currentPeriod();
  const out = [];
  for (const b of budgets) {
    if (isDeleted(b[f.del])) continue;
    const inForce = amounts.filter((x) => x[a.budget] === b[f.uid] && !isDeleted(x[a.del]) && num(x[a.period]) <= now).sort((x, y) => num(y[a.period]) - num(x[a.period]))[0];
    if (!inForce || num(inForce[a.amount]) <= 0) continue;
    const total = f.isTotal && String(b[f.isTotal]) === "1" || !b[f.target];
    out.push({ targetUid: total ? null : String(b[f.target]), amount: num(inForce[a.amount]) });
  }
  return out;
}
function readAndroid(db, warnings) {
  const version = db.prepare("PRAGMA user_version").get().user_version;
  if (version < 16) throw new Error(`Backup schema v${version} predates text uids (v16). Open it in a current Money Manager and back up again.`);
  if (version < 18) warnings.push(`Schema v${version}: transactions may lack ctgUid/toAssetUid.`);
  const t = tableNames(db);
  const settings = {};
  if (t.has("ZETC")) {
    for (const r of rows(db, "ZETC")) {
      if (isDeleted(r.isDel)) continue;
      if (String(r.ZDATATYPE) === "-23459" && r.ZDATA) settings.month_start_day = String(Math.min(28, Math.max(1, num(r.ZDATA))));
      if (String(r.ZDATATYPE) === "10002" && r.ZDATA !== null) settings.week_start = String(num(r.ZDATA) === 1 ? 1 : 0);
    }
  }
  if (t.has("CURRENCY")) {
    const main = rows(db, "CURRENCY").find((r) => String(r.IS_MAIN_CURRENCY) === "1" && !isDeleted(r.IS_DEL));
    if (main?.ISO) settings.currency = String(main.ISO);
  }
  return {
    groups: rows(db, "ASSETGROUP").filter((r) => !isDeleted(r.IS_DEL)).map((r) => ({ uid: String(r.uid), name: String(r.ACC_GROUP_NAME ?? GROUP_TYPES[num(r.TYPE)] ?? "Others"), type: num(r.TYPE), order: num(r.ORDERSEQ) })),
    accounts: rows(db, "ASSETS").map((r) => ({
      uid: String(r.uid),
      groupUid: String(r.groupUid),
      name: String(r.NIC_NAME ?? ""),
      order: num(r.ORDERSEQ),
      status: num(r.ZDATA),
      excludeFromTotals: String(r.ZDATA2) === "1",
      memo: String(r.ZDATA1 ?? "")
    })),
    categories: rows(db, "ZCATEGORY").filter((r) => !isDeleted(r.C_IS_DEL)).map((r) => ({
      uid: String(r.uid),
      name: String(r.NAME ?? ""),
      type: num(r.TYPE) === 0 ? "income" : "expense",
      parentUid: String(r.STATUS) === "2" && r.pUid && r.pUid !== "0" ? String(r.pUid) : null,
      order: num(r.ORDERSEQ)
    })),
    txs: rows(db, "INOUTCOME").filter((r) => !isDeleted(r.IS_DEL)).map((r) => ({
      uid: String(r.uid),
      doType: num(r.DO_TYPE),
      amount: num(r.ZMONEY),
      dateMs: r.ZDATE ? num(r.ZDATE) : Date.parse(`${r.WDATE}T12:00:00`),
      assetUid: String(r.assetUid ?? ""),
      toAssetUid: String(r.toAssetUid ?? ""),
      ctgUid: String(r.ctgUid ?? ""),
      note: String(r.ZCONTENT ?? ""),
      memo: String(r.ZDATA ?? ""),
      utime: num(r.UTIME)
    })),
    budgets: t.has("BUDGET") && t.has("BUDGET_AMOUNT") ? effectiveBudgets(
      rows(db, "BUDGET"),
      rows(db, "BUDGET_AMOUNT"),
      { uid: "uid", target: "targetUid", isTotal: "IS_TOTAL", del: "IS_DEL" },
      { budget: "budgetUid", amount: "AMOUNT", period: "BUDGET_PERIOD", del: "IS_DEL" }
    ) : [],
    settings
  };
}
function readIphone(db, warnings) {
  const t = tableNames(db);
  const assetCols = columns(db, "ZASSET");
  const txCols = columns(db, "ZINOUTCOME");
  if (!txCols.has("ZUID") || !assetCols.has("ZUID")) {
    throw new Error("This iPhone backup uses the old integer-id format (app build < 2192). Update Money Manager on the phone and back up again.");
  }
  const need = (cols, table, ...names) => {
    const found = pick(cols, ...names);
    if (!found) throw new Error(`${table} has none of ${names.join("/")}. Run with --inspect and share the output.`);
    return found;
  };
  let groups = [];
  if (t.has("ZASSETGROUP")) {
    const c = columns(db, "ZASSETGROUP");
    const uid = pick(c, "ZUID");
    const type = pick(c, "ZTYPE", "ZGROUPTYPE", "ZSTATUS");
    groups = rows(db, "ZASSETGROUP").filter((r) => !isDeleted(r.ZISDEL)).map((r) => ({
      uid: String(uid ? r[uid] : r[type ?? "Z_PK"]),
      name: String(r.ZASSETGROUPNAME ?? GROUP_TYPES[num(type ? r[type] : 7)] ?? "Others"),
      type: num(type ? r[type] : 7),
      order: num(r.ZORDERSEQ ?? r.ZORDER ?? r.Z_PK)
    }));
  }
  const accounts = rows(db, "ZASSET").map((r) => ({
    uid: String(r.ZUID),
    groupUid: String(r.ZGROUPUID ?? "11"),
    name: String(r.ZNICNAME ?? ""),
    order: num(r.ZORDER),
    status: num(r.ZISDEL),
    excludeFromTotals: num(r.ZISREFLECT) === 1,
    memo: String(r.ZMEMO ?? r.ZZDATA1 ?? "")
  }));
  for (const a of accounts) {
    if (!groups.some((g) => g.uid === a.groupUid)) {
      const type = num(a.groupUid);
      groups.push({ uid: a.groupUid, name: GROUP_TYPES[type] ?? `Group ${a.groupUid}`, type, order: Object.keys(GROUP_TYPES).indexOf(String(type)) });
    }
  }
  const catCols = columns(db, "ZCATEGORY");
  const catType = pick(catCols, "ZTYPE", "ZDO_TYPE", "ZDOTYPE", "ZINOUTTYPE");
  const catName = need(catCols, "ZCATEGORY", "ZNAME", "ZCATEGORYNAME", "ZTITLE");
  const categories = rows(db, "ZCATEGORY").filter((r) => !isDeleted(r.ZISDEL)).map((r) => ({
    uid: String(r.ZUID),
    name: String(r[catName] ?? ""),
    type: catType ? num(r[catType]) === 0 ? "income" : "expense" : null,
    parentUid: r.ZPUID && String(r.ZPUID) !== "0" ? String(r.ZPUID) : null,
    order: num(r.ZORDER ?? r.ZORDERSEQ)
  }));
  if (!catType) warnings.push("ZCATEGORY has no type column; inferring income/expense from transactions.");
  const amountCol = need(txCols, "ZINOUTCOME", "ZAMOUNT", "ZMONEY");
  const memoCol = pick(txCols, "ZMEMO", "ZZDATA");
  const txs = rows(db, "ZINOUTCOME").filter((r) => !isDeleted(r.ZISDEL) && String(r.ZCARDDIVIDMONTH ?? "") !== "1903911").map((r) => {
    const sub = r.ZZDATA2 && String(r.ZZDATA2) !== "0" ? String(r.ZZDATA2) : "";
    return {
      uid: String(r.ZUID),
      doType: num(r.ZDO_TYPE),
      amount: Math.abs(num(r[amountCol])),
      dateMs: (num(r.ZDATE) + 978307200) * 1e3,
      assetUid: String(r.ZASSETUID ?? ""),
      toAssetUid: String(r.ZTOASSETUID ?? ""),
      ctgUid: sub || String(r.ZCATEGORYUID ?? ""),
      note: String(r.ZCONTENT ?? ""),
      memo: memoCol ? String(r[memoCol] ?? "") : "",
      utime: num(r.ZUTIME)
    };
  });
  let budgets = [];
  if (t.has("ZBUDGET") && t.has("ZBUDGETAMOUNT")) {
    const bc = columns(db, "ZBUDGET");
    budgets = effectiveBudgets(
      rows(db, "ZBUDGET"),
      rows(db, "ZBUDGETAMOUNT"),
      { uid: "ZUID", target: "ZTARGETUID", isTotal: pick(bc, "ZISTOTAL", "ZTOTALTYPEINT"), del: "ZISDEL" },
      { budget: "ZBUDGETUID", amount: "ZAMOUNT", period: "ZBUDGETPERIOD", del: "ZISDEL" }
    );
  }
  const settings = {};
  if (t.has("ZCURRENCY")) {
    const main = rows(db, "ZCURRENCY").find((r) => String(r.ZISMAINCURRENCY) === "1" && !isDeleted(r.ZISDEL));
    if (main?.ZISO) settings.currency = String(main.ZISO);
  }
  return { groups, accounts, categories, txs, budgets, settings };
}
function convert(db, timezone) {
  const t = tableNames(db);
  const warnings = [];
  let flavor;
  let n;
  if (t.has("INOUTCOME") && t.has("ASSETS")) {
    flavor = "android";
    n = readAndroid(db, warnings);
  } else if (t.has("ZINOUTCOME") && t.has("ZASSET")) {
    flavor = "iphone";
    n = readIphone(db, warnings);
  } else {
    throw new Error("Not a Money Manager backup (no INOUTCOME/ZINOUTCOME table).");
  }
  const id = (kind, uid) => `mm-${kind}-${uid}`;
  const votes = /* @__PURE__ */ new Map();
  for (const tx of n.txs) if (tx.doType === 0 || tx.doType === 1) votes.set(tx.ctgUid, (votes.get(tx.ctgUid) ?? 0) + (tx.doType === 0 ? 1 : -1));
  const catType = (c) => {
    if (c.type) return c.type;
    const own = votes.get(c.uid) ?? 0;
    const kids = n.categories.filter((k) => k.parentUid === c.uid).reduce((s, k) => s + (votes.get(k.uid) ?? 0), 0);
    return own + kids > 0 ? "income" : "expense";
  };
  const catByUid = new Map(n.categories.map((c) => [c.uid, c]));
  const categories = n.categories.map((c) => {
    const parent = c.parentUid ? catByUid.get(c.parentUid) : void 0;
    const { icon, name } = splitEmoji(c.name);
    return { id: id("c", c.uid), type: catType(parent ?? c), name, icon, parent_id: parent ? id("c", parent.uid) : null, sort: c.order };
  });
  const groupIds = new Set(n.groups.map((g) => g.uid));
  const initial = /* @__PURE__ */ new Map();
  const accounts = n.accounts.map((a) => ({
    id: id("a", a.uid),
    group_id: id("g", groupIds.has(a.groupUid) ? a.groupUid : n.groups[0]?.uid ?? "7"),
    name: a.name,
    initial_balance: 0,
    currency: null,
    include_in_totals: a.excludeFromTotals || a.status === 1 || a.status === 2 ? 0 : 1,
    hidden: a.status === 0 ? 0 : 1,
    note: a.memo,
    sort: a.order
  }));
  const accountIds = new Set(n.accounts.map((a) => a.uid));
  const transactions = [];
  let skipped = 0;
  for (const tx of n.txs) {
    if (!accountIds.has(tx.assetUid)) {
      skipped++;
      continue;
    }
    if (tx.doType === 7 || tx.doType === 8) {
      initial.set(tx.assetUid, (initial.get(tx.assetUid) ?? 0) + (tx.doType === 7 ? tx.amount : -tx.amount));
      continue;
    }
    if (tx.doType === 4 || !(tx.doType === 0 || tx.doType === 1 || tx.doType === 3) || tx.amount === 0) {
      if (tx.doType !== 4) skipped++;
      continue;
    }
    const isTransfer = tx.doType === 3;
    if (isTransfer && !accountIds.has(tx.toAssetUid)) {
      skipped++;
      continue;
    }
    const cat = !isTransfer && catByUid.has(tx.ctgUid) ? id("c", tx.ctgUid) : null;
    transactions.push({
      id: id("t", tx.uid),
      type: isTransfer ? "transfer" : tx.doType === 0 ? "income" : "expense",
      date: localDateTime(tx.dateMs, timezone),
      amount: Math.round(Math.abs(tx.amount) * 100) / 100,
      account_id: id("a", tx.assetUid),
      to_account_id: isTransfer ? id("a", tx.toAssetUid) : null,
      category_id: cat,
      note: tx.note || (tx.ctgUid === "-4" ? "Modified Bal." : ""),
      description: tx.memo,
      source: "import",
      created_at: tx.utime || tx.dateMs
    });
  }
  for (const a of accounts) a.initial_balance = Math.round((initial.get(a.id.slice(5)) ?? 0) * 100) / 100;
  const used = new Set(transactions.flatMap((t2) => [t2.account_id, t2.to_account_id]));
  const deleted = new Set(n.accounts.filter((a) => a.status === 1 || a.status === 2).map((a) => id("a", a.uid)));
  const kept = accounts.filter((a) => !deleted.has(a.id) || used.has(a.id) || a.initial_balance !== 0);
  if (skipped) warnings.push(`Skipped ${skipped} transactions referencing missing accounts or unsupported types.`);
  const budgets = n.budgets.filter((b) => b.targetUid === null || catByUid.has(b.targetUid)).map((b) => ({ id: id("b", b.targetUid ?? "total"), category_id: b.targetUid ? id("c", b.targetUid) : null, month: null, amount: b.amount }));
  const firstVisible = kept.find((a) => !a.hidden);
  const settings = { ...n.settings, timezone };
  if (firstVisible) settings.default_account_id = firstVisible.id;
  return {
    flavor,
    warnings,
    data: {
      account_groups: n.groups.map((g) => ({ id: id("g", g.uid), name: g.name, kind: groupKind(g.type), sort: g.order })),
      accounts: kept,
      categories,
      transactions,
      budgets,
      settings
    }
  };
}
export {
  convert,
  splitEmoji
};
