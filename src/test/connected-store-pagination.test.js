import { describe, expect, it } from 'vitest';
import { loadLearning } from '../connectedStore.js';

describe('learning data pagination', () => {
  function fakeClient() {
    // A learner can have hundreds of cycles for the same block. The database
    // may return ties in a different order on each independently fetched page.
    const rows=Array.from({length:501},(_,i)=>({user_id:'learner',block_id:'block',assignment_id:String(i).padStart(4,'0')}));
    const orders=[];
    const query=(name,isRpc=false)=>{
      const keys=[];
      return {
        select(){return this}, order(key){keys.push(key);return this},
        async range(start,end){
          if (name !== 'course_block_progress' || isRpc) return {data:[],error:null};
          orders.push([...keys]);
          let list=[...rows];
          if (keys.includes('assignment_id')) list.sort((a,b)=>a.assignment_id.localeCompare(b.assignment_id));
          else if (start>0) list.reverse(); // valid but different ordering of equal keys
          return {data:list.slice(start,end+1),error:null};
        },
      };
    };
    return {orders, from:name=>query(name), rpc:name=>query(name,true)};
  }
  it('orders refresher progress by its unique cycle key across pages',async()=>{
    const client=fakeClient();const learning=await loadLearning(client,true);
    expect(client.orders).toEqual([['user_id','block_id','assignment_id'],['user_id','block_id','assignment_id']]);
    expect(learning.progress).toHaveLength(501);
    expect(new Set(learning.progress.map(row=>row.assignment_id)).size).toBe(501);
  });
  it('does not query the task 5 column when certificates are disabled',async()=>{
    const client=fakeClient();await loadLearning(client,false);
    expect(client.orders[0]).toEqual(['user_id','block_id']);
  });
});
