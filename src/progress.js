// Counts self-reported reading of text blocks only. It is not course completion.
export function textProgress(learning, courseId, userId, assignmentId = null) {
  const moduleIds = new Set(learning.modules.filter(m => m.course_id === courseId).map(m => m.id));
  const blocks = learning.blocks.filter(b => moduleIds.has(b.module_id) && (!b.block_type || b.block_type === 'text'));
  const marked = new Set((learning.progress || []).filter(p => p.user_id === userId && (!assignmentId || p.assignment_id === assignmentId)).map(p => p.block_id));
  return { read: blocks.filter(b => marked.has(b.id)).length, total: blocks.length };
}
