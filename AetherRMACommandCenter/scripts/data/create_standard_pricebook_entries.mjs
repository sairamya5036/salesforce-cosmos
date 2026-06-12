import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const targetOrg = process.argv[2] || process.env.SF_TARGET_ORG;
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

if (!targetOrg) {
  console.error('Usage: node scripts/data/create_standard_pricebook_entries.mjs <target-org>');
  process.exit(1);
}

const repoPath = (file) => resolve(repoRoot, file);

const readJson = (file) => JSON.parse(readFileSync(repoPath(file), 'utf8'));

const runSfJson = (args) => {
  const output = execFileSync('sf', [...args, '--target-org', targetOrg, '--json'], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  return JSON.parse(output);
};

const soqlString = (value) => String(value).replace(/'/g, "\\'");

const queryOne = (query) => {
  const response = runSfJson(['data', 'query', '--query', query]);
  const records = response.result?.records || [];
  return records[0];
};

const createRecord = (sobject, values) => {
  const valueString = Object.entries(values)
    .map(([key, value]) => `${key}='${soqlString(value)}'`)
    .join(' ');
  return runSfJson(['data', 'create', 'record', '--sobject', sobject, '--values', valueString]);
};

const updateRecord = (sobject, recordId, values) => {
  const valueString = Object.entries(values)
    .map(([key, value]) => `${key}='${soqlString(value)}'`)
    .join(' ');
  return runSfJson(['data', 'update', 'record', '--sobject', sobject, '--record-id', recordId, '--values', valueString]);
};

const clone = (value) => JSON.parse(JSON.stringify(value));

const writeJson = (file, value) => writeFileSync(repoPath(file), `${JSON.stringify(value, null, 2)}\n`);

const products = readJson('data/aether_import_test_data/Product2.json').records;
const customEntries = readJson('data/aether_import_test_data/PricebookEntry.json').records;
const pricebooks = readJson('data/aether_import_test_data/Pricebook2.json').records;
const accounts = readJson('data/aether_import_test_data/Account.json').records;
const contacts = readJson('data/aether_import_test_data/Contact.json').records;
const assets = readJson('data/aether_import_test_data/Asset.json').records;
const serviceContracts = readJson('data/aether_import_test_data/ServiceContract.json').records;
const productByRef = new Map(products.map((record) => [record.attributes.referenceId, record]));
const accountByRef = new Map(accounts.map((record) => [record.attributes.referenceId, record]));
const contactByRef = new Map(contacts.map((record) => [record.attributes.referenceId, record]));
const assetByRef = new Map(assets.map((record) => [record.attributes.referenceId, record]));
const serviceContractByRef = new Map(serviceContracts.map((record) => [record.attributes.referenceId, record]));

const standardPricebook = queryOne('SELECT Id, IsActive FROM Pricebook2 WHERE IsStandard = true LIMIT 1');

if (!standardPricebook) {
  throw new Error('Could not find the Standard Price Book in the target org.');
}

const standardPricebookId = standardPricebook.Id;
const aetherRmaRecordType = queryOne(
  "SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND DeveloperName = 'Aether_RMA' LIMIT 1"
);

if (!aetherRmaRecordType) {
  throw new Error('Could not find Case record type Aether_RMA. Deploy metadata before importing phase 2 data.');
}

for (const entry of customEntries) {
  const productRef = String(entry.Product2Id || '').replace(/^@/, '');
  const productSeed = productByRef.get(productRef);

  if (!productSeed?.ProductCode) {
    throw new Error(`Could not map custom entry ${entry.attributes.referenceId} to a ProductCode.`);
  }

  const product = queryOne(
    `SELECT Id FROM Product2 WHERE ProductCode = '${soqlString(productSeed.ProductCode)}' ORDER BY CreatedDate DESC LIMIT 1`
  );

  if (!product) {
    throw new Error(`Could not find Product2 with ProductCode ${productSeed.ProductCode}. Import phase 1 first.`);
  }

  const existingEntry = queryOne(
    `SELECT Id FROM PricebookEntry WHERE Pricebook2Id = '${standardPricebookId}' AND Product2Id = '${product.Id}' LIMIT 1`
  );

  if (existingEntry) {
    console.log(`Standard Price Book entry already exists for ${productSeed.ProductCode}: ${existingEntry.Id}`);
    continue;
  }

  const unitPrice = entry.UnitPrice ?? 0;
  const result = createRecord('PricebookEntry', {
    Pricebook2Id: standardPricebookId,
    Product2Id: product.Id,
    UnitPrice: unitPrice,
    IsActive: true,
  });

  console.log(`Created Standard Price Book entry for ${productSeed.ProductCode}: ${result.result?.id}`);
}

const productIdByRef = new Map();
const accountIdByRef = new Map();
const contactIdByRef = new Map();
const assetIdByRef = new Map();
const serviceContractIdByRef = new Map();
const pricebookIdByRef = new Map();

for (const record of products) {
  const product = queryOne(
    `SELECT Id FROM Product2 WHERE ProductCode = '${soqlString(record.ProductCode)}' ORDER BY CreatedDate DESC LIMIT 1`
  );
  if (!product) throw new Error(`Could not find Product2 with ProductCode ${record.ProductCode}.`);
  productIdByRef.set(record.attributes.referenceId, product.Id);
}

for (const record of pricebooks) {
  const pricebook = queryOne(
    `SELECT Id FROM Pricebook2 WHERE Name = '${soqlString(record.Name)}' ORDER BY CreatedDate DESC LIMIT 1`
  );
  if (!pricebook) throw new Error(`Could not find Pricebook2 named ${record.Name}.`);
  pricebookIdByRef.set(record.attributes.referenceId, pricebook.Id);
}

for (const record of accounts) {
  const account = queryOne(
    `SELECT Id FROM Account WHERE Name = '${soqlString(record.Name)}' ORDER BY CreatedDate DESC LIMIT 1`
  );
  if (!account) throw new Error(`Could not find Account named ${record.Name}.`);
  accountIdByRef.set(record.attributes.referenceId, account.Id);
}

for (const record of contacts) {
  const accountRef = String(record.AccountId || '').replace(/^@/, '').replace(/^\@\{([^\.]+)\.id\}$/, '$1');
  const accountId = accountIdByRef.get(accountRef);
  const accountClause = accountId ? ` AND AccountId = '${accountId}'` : '';
  const contact = queryOne(
    `SELECT Id FROM Contact WHERE LastName = '${soqlString(record.LastName)}'${accountClause} ORDER BY CreatedDate DESC LIMIT 1`
  );
  if (!contact) throw new Error(`Could not find Contact named ${record.LastName}.`);
  contactIdByRef.set(record.attributes.referenceId, contact.Id);
}

for (const record of assets) {
  const asset = queryOne(
    `SELECT Id FROM Asset WHERE Name = '${soqlString(record.Name)}' ORDER BY CreatedDate DESC LIMIT 1`
  );
  if (!asset) throw new Error(`Could not find Asset named ${record.Name}.`);
  assetIdByRef.set(record.attributes.referenceId, asset.Id);
}

for (const record of serviceContracts) {
  const accountRef = String(record.AccountId || '').replace(/^@/, '').replace(/^\@\{([^\.]+)\.id\}$/, '$1');
  const accountId = accountIdByRef.get(accountRef);
  const accountClause = accountId ? `AccountId = '${accountId}' AND ` : '';
  const nameClause = record.Name ? `Name = '${soqlString(record.Name)}' AND ` : '';
  const serviceContract = queryOne(
    `SELECT Id, Pricebook2Id FROM ServiceContract WHERE ${nameClause}${accountClause}StartDate = ${record.StartDate} AND EndDate = ${record.EndDate} ORDER BY CreatedDate DESC LIMIT 1`
  );
  if (!serviceContract) {
    throw new Error(`Could not find ServiceContract ${record.Name || ''} for ${record.StartDate} - ${record.EndDate}.`);
  }
  const pricebookRef = String(record.Pricebook2Id || '').replace(/^@/, '').replace(/^\@\{([^\.]+)\.id\}$/, '$1');
  const pricebookId = pricebookIdByRef.get(pricebookRef);
  if (pricebookId && serviceContract.Pricebook2Id !== pricebookId) {
    updateRecord('ServiceContract', serviceContract.Id, { Pricebook2Id: pricebookId });
    console.log(`Updated ServiceContract ${serviceContract.Id} to use Pricebook2 ${pricebookId}.`);
  }
  serviceContractIdByRef.set(record.attributes.referenceId, serviceContract.Id);
}

const refIds = new Map([
  ...productIdByRef,
  ...accountIdByRef,
  ...contactIdByRef,
  ...assetIdByRef,
  ...serviceContractIdByRef,
  ...pricebookIdByRef,
  ['caseRecordTypeAetherRma', aetherRmaRecordType.Id],
]);

const missingCustomPricebookEntries = [];

for (const entry of customEntries) {
  const productRef = String(entry.Product2Id || '').replace(/^@/, '').replace(/^\@\{([^\.]+)\.id\}$/, '$1');
  const pricebookRef = String(entry.Pricebook2Id || '').replace(/^@/, '').replace(/^\@\{([^\.]+)\.id\}$/, '$1');
  const productId = productIdByRef.get(productRef);
  const pricebookId = pricebookIdByRef.get(pricebookRef);

  if (!productId || !pricebookId) {
    missingCustomPricebookEntries.push(entry);
    continue;
  }

  const existingEntry = queryOne(
    `SELECT Id FROM PricebookEntry WHERE Pricebook2Id = '${pricebookId}' AND Product2Id = '${productId}' LIMIT 1`
  );

  if (existingEntry) {
    refIds.set(entry.attributes.referenceId, existingEntry.Id);
    console.log(`Custom PricebookEntry already exists for ${entry.attributes.referenceId}: ${existingEntry.Id}`);
  } else {
    missingCustomPricebookEntries.push(entry);
  }
}

const replaceExistingRefs = (value) => {
  if (typeof value === 'string') {
    const simpleRef = value.match(/^@([A-Za-z0-9_]+)$/);
    const treeRef = value.match(/^@\{([A-Za-z0-9_]+)\.id\}$/);
    const ref = simpleRef?.[1] || treeRef?.[1];
    return refIds.get(ref) || value;
  }
  if (Array.isArray(value)) return value.map(replaceExistingRefs);
  if (value && typeof value === 'object') {
    for (const key of Object.keys(value)) {
      value[key] = replaceExistingRefs(value[key]);
    }
  }
  return value;
};

mkdirSync(repoPath('data/aether_import_runtime'), { recursive: true });

if (missingCustomPricebookEntries.length > 0) {
  const runtimePricebookEntries = replaceExistingRefs(clone({ records: missingCustomPricebookEntries }));
  writeJson('data/aether_import_runtime/PricebookEntry.json', runtimePricebookEntries);
} else {
  writeJson('data/aether_import_runtime/PricebookEntry.json', { records: [] });
}

const phase2Sources = [
  ['ContractLineItem', 'data/aether_import_test_data/ContractLineItem.json'],
  ['Entitlement', 'data/aether_import_test_data/EntitlementByContractLineItem.json'],
  ['Case', 'data/aether_import_test_data/Case.json'],
];

for (const [objectName, sourcePath] of phase2Sources) {
  const source = readJson(sourcePath);
  const runtime = replaceExistingRefs(clone(source));
  writeJson(`data/aether_import_runtime/${objectName}.json`, runtime);
}

const phase2Plan = [];

if (missingCustomPricebookEntries.length > 0) {
  phase2Plan.push({
    sobject: 'PricebookEntry',
    files: ['data/aether_import_runtime/PricebookEntry.json'],
    saveRefs: true,
    resolveRefs: true,
  });
}

phase2Plan.push(
  {
    sobject: 'ContractLineItem',
    files: ['data/aether_import_runtime/ContractLineItem.json'],
    saveRefs: true,
    resolveRefs: true,
  },
  {
    sobject: 'Entitlement',
    files: ['data/aether_import_runtime/Entitlement.json'],
    saveRefs: true,
    resolveRefs: true,
  },
  {
    sobject: 'Case',
    files: ['data/aether_import_runtime/Case.json'],
    saveRefs: true,
    resolveRefs: true,
  }
);

writeJson('aether_import_phase2_runtime.json', phase2Plan);

console.log(`Generated ${repoPath('aether_import_phase2_runtime.json')} with target-org IDs for phase-1 records.`);
