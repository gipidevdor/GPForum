/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const source = fs.readFileSync(`${__dirname}/../../assets/js/notifications.js`, "utf8");
const tick = async () => { for (let i=0;i<5;i++) await new Promise(setImmediate); };
function harness({ guest=false, initial, hidden=false, realtime=false, inbox=false }={}) {
  let now=100000;
  let answer={status:200, count:3};
  let held;
  const requests=[];
  const sockets=[];
  const timers=new Map();
  const events={};
  const badge={hidden:true,textContent:""};
  const updates=inbox?{hidden:true}:null;
  const link={dataset:{summaryUrl:"/notifications/summary",notificationLabel:"Notifiche"},
    attributes:{},querySelector:()=>badge,setAttribute(name,value){this.attributes[name]=value;}};
  if(realtime) { link.dataset.realtimeUrl="/forum/realtime"; link.dataset.realtimeChannel="notifications:user-1"; }
  class Socket {
    constructor(url) { this.url=url; this.events={}; this.sent=[]; this.closed=false; sockets.push(this); }
    addEventListener(name,fn){this.events[name]=fn;}
    send(text){this.sent.push(JSON.parse(text));}
    close(){this.closed=true;this.events.close?.({code:1000});}
    message(value){this.events.message?.({data: typeof value === "string" ? value : JSON.stringify(value)});}
  }
  if(initial!==undefined)link.dataset.initialCount=String(initial);
  const document={hidden,querySelector:(selector)=>selector === "[data-notification-update]" ? updates : selector === "[data-notification-link]" && !guest ? link : null,addEventListener(name,fn){events[name]=fn;}};
  vm.runInNewContext(source,{document,window:{WebSocket:realtime?Socket:undefined,location:{href:"https://forum.test/forum/t/one",origin:"https://forum.test"},addEventListener(name,fn){events[name]=fn;}},
    URL, Date:{now:()=>now},clearTimeout(id){timers.delete(id);},setTimeout(fn,delay){const id={};timers.set(id,{fn,delay});return id;},
    fetch:async(url,options)=>{requests.push({url,options});if(held)await held;return {status:answer.status,ok:answer.status===200,json:async()=>({unread_count:answer.count})};}});
  return{requests,sockets,timers,events,badge,updates,link,document,
    advance(){now+=60000;},answer(value){answer=value;},hold(){let release;held=new Promise(resolve=>release=resolve);return()=>{held=null;release();};},
    async timer(delay){const entry=[...timers].find(([,value])=>delay===undefined||value.delay===delay);if(entry){timers.delete(entry[0]);await entry[1].fn();}await tick();}};
}
test("guests do no notification work",async()=>{const p=harness({guest:true});await tick();assert.equal(p.requests.length,0);assert.equal(p.timers.size,0);});
test("badge requests count only and caps its display",async()=>{const p=harness();await tick();assert.equal(p.requests.length,1);assert.equal(p.requests[0].url,"/notifications/summary");assert.equal(p.requests[0].options.cache,"no-store");assert.equal(p.badge.textContent,"3");assert.equal(p.link.attributes["aria-label"],"Notifiche: 3");p.answer({status:200,count:100});p.advance();await p.timer();assert.equal(p.badge.textContent,"99+");});
test("inbox reuses its server count without another read",async()=>{const p=harness({initial:8});await tick();assert.equal(p.requests.length,0);assert.equal(p.badge.textContent,"8");assert.equal(p.timers.size,1);});
test("hidden tabs stop timers and refresh on return when stale",async()=>{const p=harness({hidden:true});await tick();assert.equal(p.requests.length,0);p.document.hidden=false;p.events.visibilitychange();await tick();assert.equal(p.requests.length,1);p.document.hidden=true;p.events.visibilitychange();assert.equal(p.timers.size,0);p.advance();p.document.hidden=false;p.events.visibilitychange();await tick();assert.equal(p.requests.length,2);});
test("focus bursts coalesce and never start concurrent requests",async()=>{const p=harness({initial:1});p.advance();const release=p.hold();p.events.focus();p.events.focus();p.events.pageshow();assert.equal(p.requests.length,1);release();await tick();p.events.focus();assert.equal(p.requests.length,1);});
test("failures and invalid counts preserve the last known badge",async()=>{const p=harness({initial:4});p.answer({status:503});p.advance();await p.timer();assert.equal(p.badge.textContent,"4");p.answer({status:200,count:-1});p.advance();await p.timer();assert.equal(p.badge.textContent,"4");});
test("zero hides the badge; expired sessions stop updates",async()=>{const p=harness({initial:4});p.answer({status:200,count:0});p.advance();await p.timer();assert.equal(p.badge.hidden,true);p.answer({status:401});p.advance();await p.timer();assert.equal(p.timers.size,0);p.advance();p.events.focus();assert.equal(p.requests.length,2);});

function subscribe(socket) {
  socket.message({type:"realtime.connected", connection_id:"one"});
  socket.message({type:"subscribed", channel:"notifications:user-1"});
}
function push(socket, count, recipient="user-1") {
  socket.message({type:"notification.badge", aggregate_id:recipient, payload:{unread_count:count}});
}
test("websocket handshake subscribes only to the member channel and uses wss",async()=>{
  const p=harness({realtime:true});
  assert.equal(p.requests.length,0);
  assert.equal(p.sockets[0].url,"wss://forum.test/forum/realtime");
  subscribe(p.sockets[0]);
  assert.equal(JSON.stringify(p.sockets[0].sent),JSON.stringify([{type:"subscribe",channel:"notifications:user-1"}]));
  push(p.sockets[0],7);
  assert.equal(p.badge.textContent,"7");
  assert.equal(p.timers.size,0);
  p.advance();p.events.focus();p.events.pageshow();await tick();
  assert.equal(p.requests.length,0);
  assert.equal(p.sockets.length,1);
  push(p.sockets[0],0);assert.equal(p.badge.hidden,true);
});
test("unsubscribed, malformed, foreign and invalid pushes cannot change the badge",()=>{
  const p=harness({realtime:true,initial:2});const ws=p.sockets[0];
  push(ws,50);assert.equal(p.badge.textContent,"2");
  subscribe(ws);ws.message("{bad");ws.message(null);push(ws,99,"user-2");push(ws,-1);push(ws,"9");
  assert.equal(p.badge.textContent,"2");
  push(ws,100);assert.equal(p.badge.textContent,"99+");
});
test("missing subscription snapshot times out to fallback and bounded reconnect",async()=>{
  const p=harness({realtime:true});const old=p.sockets[0];subscribe(old);
  await p.timer(10000);
  assert.equal(old.closed,true);assert.equal(p.requests.length,1);
  const retry=[...p.timers.values()].find(x=>x.delay<2000);
  assert.ok(retry.delay>=1000);
  p.events.focus();p.events.focus();assert.equal(p.sockets.length,1);
  await p.timer(retry.delay);assert.equal(p.sockets.length,2);
  subscribe(p.sockets[1]);push(p.sockets[1],8);
  assert.equal(p.badge.textContent,"8");assert.equal(p.timers.size,0);
});
test("an older HTTP fallback cannot overwrite a newer websocket snapshot",async()=>{
  const p=harness({realtime:true});const release=p.hold();
  await p.timer(10000);
  const retry=[...p.timers.values()].find(x=>x.delay<2000);
  await p.timer(retry.delay);subscribe(p.sockets[1]);push(p.sockets[1],9);
  release();await tick();assert.equal(p.badge.textContent,"9");assert.equal(p.timers.size,0);
});
test("hidden tabs and page cache release sockets and reconnect to a fresh snapshot",()=>{
  const p=harness({realtime:true});const old=p.sockets[0];subscribe(old);push(old,5);
  p.document.hidden=true;p.events.visibilitychange();assert.equal(old.closed,true);assert.equal(p.timers.size,0);
  push(old,6);assert.equal(p.badge.textContent,"5");
  p.document.hidden=false;p.events.visibilitychange();assert.equal(p.sockets.length,2);
  subscribe(p.sockets[1]);push(p.sockets[1],7);assert.equal(p.badge.textContent,"7");
  p.events.pagehide();assert.equal(p.sockets[1].closed,true);
  p.events.focus();assert.equal(p.sockets.length,2);
  p.events.pageshow();assert.equal(p.sockets.length,3);
});
test("revoked sessions clear the badge and never reconnect",()=>{
  const p=harness({realtime:true,initial:5});const ws=p.sockets[0];subscribe(ws);push(ws,5);
  ws.events.close({code:1008});assert.equal(p.badge.hidden,true);assert.equal(p.timers.size,0);
  p.events.focus();p.events.online();assert.equal(p.sockets.length,1);assert.equal(p.requests.length,0);
});
test("subscription denial uses HTTP without retrying a forbidden channel",async()=>{
  const p=harness({realtime:true});p.sockets[0].message({type:"error",reason:"wrong_recipient"});await tick();
  assert.equal(p.requests.length,1);assert.equal(p.sockets[0].closed,true);
  p.events.focus();assert.equal(p.sockets.length,1);
});

test("inbox announces changed state without fetching or replacing rows",()=>{
  const p=harness({realtime:true,initial:1,inbox:true});subscribe(p.sockets[0]);push(p.sockets[0],1);
  assert.equal(p.updates.hidden,true);
  push(p.sockets[0],8);
  assert.equal(p.updates.hidden,false);
  assert.equal(p.requests.length,0);
});
