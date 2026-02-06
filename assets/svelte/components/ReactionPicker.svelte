<script>
  import { createEventDispatcher, onMount } from 'svelte'

  export let position = { x: 0, y: 0 }

  const dispatch = createEventDispatcher()

  const emojis = [
    '👍', '👎', '❤️', '😂', '😮', '😢',
    '🎉', '🚀', '👀', '💡', '✅', '❌',
    '🔥', '⭐', '💯', '🙌', '👏', '🤔'
  ]

  let pickerElement

  function selectEmoji(emoji) {
    dispatch('select', emoji)
  }

  function close(event) {
    if (pickerElement && !pickerElement.contains(event.target)) {
      dispatch('close')
    }
  }

  onMount(() => {
    // Close on click outside
    document.addEventListener('click', close)

    return () => {
      document.removeEventListener('click', close)
    }
  })
</script>

<style>
  .reaction-picker {
    position: fixed;
    background-color: white;
    border: 1px solid #ddd;
    border-radius: 0.5rem;
    padding: 0.75rem;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
    z-index: 1000;
    display: grid;
    grid-template-columns: repeat(6, 1fr);
    gap: 0.5rem;
  }

  :global(.dark) .reaction-picker {
    background-color: #2f3437;
    border-color: #444a4f;
  }

  .emoji-button {
    background: none;
    border: none;
    font-size: 1.5rem;
    width: 2.5rem;
    height: 2.5rem;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 0.25rem;
    cursor: pointer;
    transition: background-color 0.15s, transform 0.1s;
  }

  .emoji-button:hover {
    background-color: #f8f8f8;
    transform: scale(1.2);
  }

  :global(.dark) .emoji-button:hover {
    background-color: #222529;
  }

  .emoji-button:active {
    transform: scale(1.1);
  }
</style>

<div
  bind:this={pickerElement}
  class="reaction-picker"
  style="left: {position.x}px; top: {position.y}px;"
>
  {#each emojis as emoji}
    <button
      class="emoji-button"
      on:click={() => selectEmoji(emoji)}
      title={emoji}
    >
      {emoji}
    </button>
  {/each}
</div>
