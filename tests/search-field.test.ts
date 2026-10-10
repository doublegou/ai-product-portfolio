import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createElement, useState } from 'react';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { SearchField } from '../src/components/SearchField';

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

test('Chinese composition preserves drafts and only searches committed words', async () => {
  const searches: string[] = [];
  function Host() {
    const [value, setValue] = useState('');
    return createElement(SearchField, { value, label: '搜索', placeholder: '搜索', onChange: next => {
      searches.push(next);
      setValue(next);
    } });
  }
  let renderer!: ReactTestRenderer;
  await act(() => { renderer = create(createElement(Host)); });
  const input = () => renderer.root.findByType('input');
  const change = async (value: string, isComposing = false) => act(() => {
    input().props.onChange({ target: { value }, nativeEvent: { isComposing } });
  });
  await act(() => input().props.onCompositionStart());
  await change('yi', true);
  await change('异', true);
  assert.equal(input().props.value, '异');
  assert.deepEqual(searches, []);
  await act(() => input().props.onCompositionEnd({ currentTarget: { value: '异' } }));
  await change('异'); // Browsers may dispatch an input event after compositionend.
  assert.deepEqual(searches, ['异']);
  await act(() => input().props.onCompositionStart());
  await change('异ciyuan', true);
  await act(() => input().props.onCompositionEnd({ currentTarget: { value: '异次元' } }));
  assert.equal(input().props.value, '异次元');
  assert.deepEqual(searches, ['异', '异次元']);
  await change('异次元A');
  assert.equal(searches.at(-1), '异次元A');
  await act(() => renderer.root.findByType('button').props.onClick());
  assert.equal(input().props.value, '');
  assert.equal(searches.at(-1), '');
  await act(() => renderer.unmount());
});

test('search input follows external URL changes', async () => {
  let renderer!: ReactTestRenderer;
  const props = { value: '中文', label: '搜索', placeholder: '搜索', onChange: () => {} };
  await act(() => { renderer = create(createElement(SearchField, props)); });
  await act(() => renderer.update(createElement(SearchField, { ...props, value: '商家' })));
  assert.equal(renderer.root.findByType('input').props.value, '商家');
  await act(() => renderer.unmount());
});
