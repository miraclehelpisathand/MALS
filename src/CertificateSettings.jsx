import React,{useEffect,useState} from 'react';
import {CertificateEditor} from './CertificateEditor.jsx';
import {learningAction} from './connectedStore.js';

// Only mounted when task 5's feature flag is explicitly enabled.
export function CertificateSettings({client,course,learning,busy,onSave,onRemove,onCancel}) {
 const initial=(learning.certificateSettings||[]).find(s=>s.course_id===course.id);
 const [template,setTemplate]=useState(null),[loading,setLoading]=useState(!!initial),[error,setError]=useState('');
 useEffect(()=>{if(!initial)return;let alive=true;learningAction(client,'get_certificate_template',{target_template:initial.template_id}).then(data=>{if(alive)setTemplate(data)}).catch(e=>{if(alive)setError(e.message)}).finally(()=>{if(alive)setLoading(false)});return()=>{alive=false}},[client,initial?.template_id]);
 const options=[...(learning.catalog||[]),...learning.courses].filter(c=>c.status==='published'||(learning.catalog||[]).includes(c));const unique=Array.from(new Map(options.filter(c=>c.family_id).map(c=>[c.family_id,c])).values());
 if(loading)return <div className="modal-body" role="status">Loading template…</div>;
 if(error)return <div className="modal-body"><p className="auth-error" role="alert">{error}</p><button className="button secondary" onClick={onCancel}>Close</button></div>;
 return <><CertificateEditor initial={initial} initialTemplate={template} course={course} courseChoices={unique} busy={busy} onSave={onSave} onCancel={onCancel}/>{initial&&<div className="modal-body"><button className="button secondary" disabled={busy} onClick={()=>{if(window.confirm('Disable certification for this draft? Existing published versions and certificates will not change.'))onRemove()}}>Disable certification for this draft</button></div>}</>;
}
