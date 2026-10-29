import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const html=readFileSync(new URL('../dashboard.html',import.meta.url),'utf8');
const bootstrap=html.match(/<script type="module">([\s\S]*?)<\/script>/)[1];
test('session promise is defined synchronously before DOMContentLoaded',()=>{
 assert.match(bootstrap,/import \* as inventoryHistory from/);
 const prefix=bootstrap.slice(0,bootstrap.indexOf('window.initAssistant'));
 let called=false;const ready=Promise.resolve({status:'ok'});
 const context={window:{},document:{},supabase:{auth:{onAuthStateChange(){}}},inventoryTools:{createReadCache(){return {}}},inventoryHistory:{},requireInventorySession(){called=true;return ready},siteCode(){},verificarConexion(){}};
 vm.runInNewContext(prefix.replace(/^\s*import .*;\s*$/gm,''),context);
 assert.equal(called,true);assert.equal(context.window.inventoryAuthReady,ready);
 assert.equal(context.window.inventoryHistory,context.inventoryHistory);
});

