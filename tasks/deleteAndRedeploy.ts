import { exec } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

// ...

// Sanitize the contract name to prevent shell injection
const sanitizedContractName = taskArgs.contract.replace(/[^\w]/g, '_');

// Use the sanitized contract name in the shell command
exec(`rm deployments/${network}/${sanitizedContractName}.json`, (error) => {
  if (error) {
    console.error(`Error deleting deployment file: ${error}`);
  } else {
    console.log(`Deleted deployment file for contract ${sanitizedContractName} on network ${network}`);
  }
});

// ...