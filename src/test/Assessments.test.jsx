// @vitest-environment jsdom
import React from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen, within, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AssessmentEditor, TakeAssessment, AssessmentReviewQueue } from '../Assessments.jsx';
afterEach(cleanup);
const quiz={pass_mark:70,max_attempts:2,questions:[{id:'q1',type:'multiple',prompt:'Choose safe actions',options:[{id:'a',text:'A'},{id:'b',text:'B'}]},{id:'q2',type:'short',prompt:'Explain why'}]};
const practical={criteria:[{id:'c1',text:'Prepare safely'},{id:'c2',text:'Use safely'}]};
const client={rpc:vi.fn((name,{target_block})=>Promise.resolve({data:target_block==='p1'?practical:quiz,error:null}))};
const directory={profiles:[{id:'t1',display_name:'Alex'},{id:'trainer',display_name:'Riley'}]};
describe('assessment workflows',()=>{
 it('allows an author to configure quiz questions, scoring, retries and feedback',async()=>{const user=userEvent.setup(),save=vi.fn();render(<AssessmentEditor client={client} kind="quiz" module={{id:'m1'}} busy={false} close={()=>{}} onSave={save}/>);await user.type(screen.getByLabelText('Assessment title'),'Safety quiz');await user.selectOptions(screen.getByLabelText('Question type'),'multiple');await user.type(screen.getByLabelText('Question text'),'Choose actions');await user.type(screen.getByLabelText('Option 1 text'),'First');await user.type(screen.getByLabelText('Option 2 text'),'Second');await user.click(screen.getByLabelText('Correct option 1'));await user.type(screen.getByLabelText(/Feedback after submission/),'Review this');await user.click(screen.getByRole('button',{name:'Save assessment'}));expect(save).toHaveBeenCalledOnce();const payload=save.mock.calls[0][0];expect(payload.kind).toBe('quiz');expect(payload.definition.questions[0].options.map(o=>o.correct)).toEqual([true,false]);expect(payload.definition.questions[0].feedback).toBe('Review this');});
 it('submits learner answers, displays result history and prevents a pending retry',async()=>{const user=userEvent.setup(),submit=vi.fn();const block={id:'q1',block_type:'quiz',body:'Complete this'};const {rerender}=render(<TakeAssessment client={client} block={block} attempts={[]} directory={directory} busy={false} preview={false} submitQuiz={submit} requestPractical={()=>{}}/>);await screen.findByText(/Choose safe actions/);await user.click(screen.getByLabelText('A'));await user.type(screen.getByLabelText('Answer to Explain why'),'Because it is safe');await user.click(screen.getByRole('button',{name:'Submit quiz'}));expect(submit).toHaveBeenCalledWith({q1:['a'],q2:'Because it is safe'});rerender(<TakeAssessment client={client} block={block} attempts={[{id:'a1',attempt_number:1,kind:'quiz',status:'pending_review',submitted_at:'2027-01-01T00:00:00Z',feedback:{}}]} directory={directory} busy={false} preview={false} submitQuiz={submit} requestPractical={()=>{}}/>);expect(screen.getByText(/Awaiting trainer review/)).toBeTruthy();expect(screen.queryByRole('button',{name:'Submit quiz'})).toBeNull();});
 it('requests practical assessment without asking trainee for evidence',async()=>{const user=userEvent.setup(),request=vi.fn();render(<TakeAssessment client={client} block={{id:'p1',block_type:'practical',body:'Demonstrate'}} attempts={[]} directory={directory} busy={false} preview={false} submitQuiz={()=>{}} requestPractical={request}/>);await screen.findByText('Prepare safely');await user.click(screen.getByRole('button',{name:'Request practical assessment'}));expect(request).toHaveBeenCalledOnce();expect(screen.queryByLabelText(/evidence/i)).toBeNull();});
 it('records trainer checklist outcomes and overall comment',async()=>{const user=userEvent.setup();const api={rpc:vi.fn((name,args)=>name==='get_assessment_definition'?Promise.resolve({data:practical,error:null}):Promise.resolve({data:null,error:null}))};const attempt={id:'a1',user_id:'t1',block_id:'p1',attempt_number:1,kind:'practical',status:'pending_review',submitted_at:'2027-01-01T00:00:00Z',answers:{}};const learning={attempts:[attempt],blocks:[{id:'p1',title:'Practical',module_id:'m1'}],modules:[{id:'m1',course_id:'c1'}],courses:[{id:'c1',title:'Safety',version_number:1}]};render(<AssessmentReviewQueue client={api} userId="trainer" learning={learning} directory={directory} refresh={async()=>true}/>);await user.click(screen.getByRole('button',{name:'Review'}));await screen.findByLabelText('Prepare safely');await user.selectOptions(screen.getByLabelText('Prepare safely'),'competent');await user.selectOptions(screen.getByLabelText('Use safely'),'not_assessed');await user.type(screen.getByLabelText(/Overall comment/),'Try again');await user.click(screen.getByRole('button',{name:'Submit review'}));await waitFor(()=>expect(api.rpc).toHaveBeenCalledWith('review_assessment',{target_attempt:'a1',decisions:{c1:'competent',c2:'not_assessed'},comment:'Try again'}));expect(await screen.findByText('Review recorded.')).toBeTruthy();});
 it('filters only visible reviews by course version and status without including own attempts',async()=>{
  const user=userEvent.setup();
  const base={attempt_number:1,kind:'practical',submitted_at:'2027-01-01T00:00:00Z',answers:{}};
  const learning={attempts:[
   {...base,id:'a1',user_id:'t1',block_id:'p1',status:'pending_review'},
   {...base,id:'a2',user_id:'t2',block_id:'p2',status:'competent'},
   {...base,id:'a3',user_id:'trainer',block_id:'p3',status:'pending_review'},
   {...base,id:'a4',user_id:'t2',block_id:'p3',status:'pending_review'},
  ],blocks:[{id:'p1',title:'First assessment',module_id:'m1'},{id:'p2',title:'Second assessment',module_id:'m2'},{id:'p3',title:'Third assessment',module_id:'m3'}],modules:[{id:'m1',course_id:'c1'},{id:'m2',course_id:'c2'},{id:'m3',course_id:'c3'}],courses:[{id:'c1',title:'Safety',version_number:1},{id:'c2',title:'Safety',version_number:2},{id:'c3',title:'Tools',version_number:1}]};
  const people={profiles:[...directory.profiles,{id:'t2',display_name:'Jordan'}]};
  const {rerender}=render(<AssessmentReviewQueue client={client} userId="trainer" learning={learning} directory={people} refresh={async()=>true}/>);
  expect(screen.getByText('3 assessments shown')).toBeTruthy();
  expect(screen.queryByText(/Riley · Third assessment/)).toBeNull();
  const course=screen.getByLabelText('Course version'),status=screen.getByLabelText('Review status');
  expect(within(course).getByRole('option',{name:'Safety · Version 1'}).value).toBe('c1');
  expect(within(course).getByRole('option',{name:'Safety · Version 2'}).value).toBe('c2');
  await user.selectOptions(course,'c2');
  expect(screen.getByText('1 assessment shown')).toBeTruthy();
  expect(screen.getByText('Jordan · Second assessment')).toBeTruthy();
  expect(screen.queryByText('Alex · First assessment')).toBeNull();
  await user.selectOptions(status,'pending_review');
  expect(screen.getByText('No matching assessments')).toBeTruthy();
  await user.selectOptions(course,'');
  expect(screen.getByText('2 assessments shown')).toBeTruthy();
  await user.selectOptions(course,'c1');
  const refreshed={...learning,attempts:learning.attempts.filter(a=>a.id!=='a1')};
  rerender(<AssessmentReviewQueue client={client} userId="trainer" learning={refreshed} directory={people} refresh={async()=>true}/>);
  await waitFor(()=>expect(course.value).toBe(''));
  expect(screen.getByText('1 assessment shown')).toBeTruthy();
 });

});
