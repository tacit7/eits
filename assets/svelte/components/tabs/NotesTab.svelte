<script>
  import { onMount } from 'svelte'
  import { formatDateTime, shortId } from '../../utils/datetime.js'
  import { formatUUID, copyToClipboard } from '../../utils/clipboard.js'
  import { getHljs } from '../../../js/hljs_instance.js'

  // Heroicons
  import ClockSvg from 'heroicons/24/outline/clock.svg'
  import DocumentTextSvg from 'heroicons/24/outline/document-text.svg'
  import PlusSvg from 'heroicons/24/outline/plus.svg'

  export let notes = []

  // marked is loaded lazily in onMount; hljs comes from shared hljs_instance.js
  // (core-only build, 6 languages). renderReady triggers re-render when ready.
  let markedParse = null
  let renderReady = false

  onMount(async () => {
    const [{ marked }, hljs] = await Promise.all([
      import('marked'),
      getHljs(),
    ])

    marked.use({
      gfm: true,
      breaks: true,
    })

    marked.use({
      highlight: function(code, lang) {
        if (lang && hljs.getLanguage(lang)) {
          try {
            return hljs.highlight(code, { language: lang }).value
          } catch (err) {
            console.error('Highlight error:', err)
          }
        }
        return hljs.highlightAuto(code).value
      }
    })

    markedParse = (content) => marked.parse(content || '')
    renderReady = true
  })

  function renderMarkdown(content, _ready) {
    if (!markedParse) return content || ''
    try {
      return markedParse(content)
    } catch (e) {
      console.error('Markdown parse error:', e)
      return content || ''
    }
  }

  function handleCopyId(id, event) {
    event.stopPropagation()
    copyToClipboard(formatUUID(id), { formatAsUUID: false })
  }
</script>

{#if notes && notes.length > 0}
  <div class="space-y-4">
    {#each notes as note (note.id)}
      <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow">
        <div class="card-body p-4">
          <!-- Markdown content; re-renders when renderReady flips true -->
          <div class="prose prose-sm max-w-none dark:prose-invert
                      prose-headings:font-semibold
                      prose-h1:text-2xl prose-h1:mb-3
                      prose-h2:text-xl prose-h2:mb-2
                      prose-h3:text-lg prose-h3:mb-2
                      prose-p:mb-2
                      prose-ul:mb-2 prose-ol:mb-2
                      prose-li:mb-1
                      prose-code:bg-base-200 prose-code:px-1 prose-code:py-0.5 prose-code:rounded
                      prose-pre:bg-base-300 prose-pre:p-3 prose-pre:rounded-lg
                      prose-blockquote:border-l-4 prose-blockquote:border-primary prose-blockquote:pl-4">
            {@html renderMarkdown(note.body, renderReady)}
          </div>

          <!-- Footer with ID and Timestamp -->
          <div class="card-actions justify-between mt-3 pt-3 border-t border-base-300">
            <!-- Note ID Badge -->
            <button
              class="badge badge-ghost badge-sm hover:badge-primary cursor-pointer font-mono transition-colors"
              on:click={(e) => handleCopyId(note.id, e)}
              title="Copy ID: {note.id}"
            >
              #{shortId(String(note.id), 8)}
            </button>

            <!-- Timestamp -->
            {#if note.created_at}
              <div class="badge badge-ghost badge-sm">
                <span class="h-3 w-3 mr-1">{@html ClockSvg}</span>
                {formatDateTime(note.created_at)}
              </div>
            {/if}
          </div>
        </div>
      </div>
    {/each}
  </div>
{:else}
  <!-- Empty state -->
  <div class="hero min-h-[400px] bg-base-200 rounded-lg">
    <div class="hero-content text-center">
      <div class="max-w-md">
        <span class="h-16 w-16 mx-auto mb-4 text-base-content/30 block">{@html DocumentTextSvg}</span>
        <h2 class="text-2xl font-bold text-base-content">No notes yet</h2>
        <p class="py-3 text-base-content/70">
          Add a note to capture decisions, blockers, or next steps for this session.
        </p>
        <button class="btn btn-primary btn-sm">
          <span class="h-4 w-4">{@html PlusSvg}</span>
          Add Your First Note
        </button>
      </div>
    </div>
  </div>
{/if}
