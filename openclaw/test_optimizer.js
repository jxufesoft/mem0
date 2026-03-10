import('./lib/setup.ts').then(({ MemoryOptimizer }) => {
  const optimizer = new MemoryOptimizer({
    l0Path: '/tmp/test_memory.md',
    l1Dir: '/tmp/test_memory',
    contextMaxKB: 100,
    l1FileMaxKB: 5,
    l1KeepRecentDays: 7,
    l0MaxLines: 100,
  });

  optimizer.optimize().then(result => {
    console.log('优化结果:', JSON.stringify(result, null, 2));
  }).then(() => {
    const fs = require('node:fs/promises');
    return fs.readFile('/tmp/test_memory/test.md', 'utf-8');
  }).then(content => {
    console.log('\n=== 压缩后文件内容 (前50行) ===');
    console.log(content.split('\n').slice(0, 50).join('\n'));
    console.log('\n✅ 压缩完成');
  }).catch(err => {
    console.error('Error:', err);
  });
});
