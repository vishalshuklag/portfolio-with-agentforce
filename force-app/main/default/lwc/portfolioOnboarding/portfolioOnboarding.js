import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateFromResume from '@salesforce/apex/PortfolioOnboardingService.generateFromResume';
import createRecords from '@salesforce/apex/PortfolioOnboardingService.createRecords';

// Salesforce-managed Models API generation models (Supported Models, Agentforce
// Developer Guide). Embeddings-only (Ada) and rerouted/retired models are omitted.
const MODEL_OPTIONS = [
    // OpenAI / Azure OpenAI
    { label: 'GPT-4o mini (OpenAI)', value: 'sfdc_ai__DefaultOpenAIGPT4OmniMini' },
    { label: 'GPT-4o mini (geo-aware)', value: 'sfdc_ai__DefaultGPT4OmniMini' },
    { label: 'GPT-4o (geo-aware)', value: 'sfdc_ai__DefaultGPT4Omni' },
    { label: 'GPT-4.1 (geo-aware)', value: 'sfdc_ai__DefaultGPT41' },
    { label: 'GPT-4.1 mini (geo-aware)', value: 'sfdc_ai__DefaultGPT41Mini' },
    { label: 'GPT-5 (geo-aware)', value: 'sfdc_ai__DefaultGPT5' },
    { label: 'GPT-5 mini (geo-aware)', value: 'sfdc_ai__DefaultGPT5Mini' },
    { label: 'GPT-5.1 (geo-aware)', value: 'sfdc_ai__DefaultGPT51' },
    { label: 'GPT-5.2 (geo-aware)', value: 'sfdc_ai__DefaultGPT52' },
    { label: 'GPT-5.4 (geo-aware)', value: 'sfdc_ai__DefaultGPT54' },
    { label: 'GPT-5.4 mini (Beta, geo-aware)', value: 'sfdc_ai__DefaultGPT54Mini' },
    { label: 'GPT-5.5 (Beta, geo-aware)', value: 'sfdc_ai__DefaultGPT55' },
    { label: 'OpenAI o3 (geo-aware)', value: 'sfdc_ai__DefaultO3' },
    { label: 'OpenAI o4 mini (geo-aware)', value: 'sfdc_ai__DefaultO4Mini' },
    // Anthropic Claude on Amazon Bedrock
    { label: 'Claude Haiku 4.5 (Bedrock)', value: 'sfdc_ai__DefaultBedrockAnthropicClaude45Haiku' },
    { label: 'Claude Sonnet 4.5 (Bedrock)', value: 'sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet' },
    { label: 'Claude Sonnet 4.6 (Bedrock)', value: 'sfdc_ai__DefaultBedrockAnthropicClaude46Sonnet' },
    { label: 'Claude Opus 4.5 (Bedrock)', value: 'sfdc_ai__DefaultBedrockAnthropicClaude45Opus' },
    { label: 'Claude Opus 4.6 (Bedrock)', value: 'sfdc_ai__DefaultBedrockAnthropicClaude46Opus' },
    { label: 'Claude Opus 4.7 (Beta, Bedrock)', value: 'sfdc_ai__DefaultBedrockAnthropicClaude47Opus' },
    // Amazon Nova on Amazon Bedrock
    { label: 'Amazon Nova Lite (Bedrock)', value: 'sfdc_ai__DefaultBedrockAmazonNovaLite' },
    { label: 'Amazon Nova Pro (Bedrock)', value: 'sfdc_ai__DefaultBedrockAmazonNovaPro' },
    // NVIDIA Nemotron on Amazon Bedrock
    {
        label: 'NVIDIA Nemotron 3 Nano 30B (Beta, Bedrock)',
        value: 'sfdc_ai__DefaultBedrockNvidiaNemotronNano330b'
    },
    {
        label: 'NVIDIA Nemotron 3 Super 120B (Beta, Bedrock)',
        value: 'sfdc_ai__DefaultBedrockNvidiaNemotronSuper3120b'
    },
    // Google Gemini on Vertex AI
    { label: 'Gemini 2.5 Flash (Vertex AI)', value: 'sfdc_ai__DefaultVertexAIGemini25Flash001' },
    { label: 'Gemini 2.5 Flash Lite (Vertex AI)', value: 'sfdc_ai__DefaultVertexAIGemini25FlashLite001' },
    { label: 'Gemini 2.5 Pro (Vertex AI)', value: 'sfdc_ai__DefaultVertexAIGeminiPro25' },
    { label: 'Gemini 3 Flash (Vertex AI)', value: 'sfdc_ai__DefaultVertexAIGemini30Flash' },
    { label: 'Gemini 3.1 Flash Lite (Beta, Vertex AI)', value: 'sfdc_ai__DefaultVertexAIGemini31FlashLite' },
    { label: 'Gemini 3.1 Pro (Beta, Vertex AI)', value: 'sfdc_ai__DefaultVertexAIGeminiPro31' },
    { label: 'Gemini 3.5 Flash (Vertex AI)', value: 'sfdc_ai__DefaultVertexAIGemini35Flash' }
];

const MONTHS = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

export default class PortfolioOnboarding extends LightningElement {
    resumeText = '';
    selectedModel = 'sfdc_ai__DefaultOpenAIGPT4OmniMini';
    includeResume = true;

    items;
    selection = [];
    generating = false;
    creating = false;
    createdCount;

    get modelOptions() {
        return MODEL_OPTIONS;
    }

    get hasItems() {
        return Array.isArray(this.items) && this.items.length > 0;
    }

    get itemCount() {
        return this.hasItems ? this.items.length : 0;
    }

    get charCount() {
        return (this.resumeText || '').length;
    }

    get busy() {
        return this.generating || this.creating;
    }

    get generateDisabled() {
        return this.busy || (this.resumeText || '').trim().length < 40;
    }

    get showCreated() {
        return this.createdCount !== undefined && this.createdCount !== null;
    }

    get showInput() {
        return !this.hasItems && !this.showCreated;
    }

    get decoratedItems() {
        if (!this.hasItems) {
            return [];
        }
        return this.items.map((i, idx) => {
            const range = this.formatRange(i.startDate, i.endDate);
            const selected = this.isSelected(idx);
            return {
                key: idx,
                name: i.name,
                itemType: i.itemType,
                subtitle: i.subtitle,
                description: i.description,
                hasSubtitle: !!i.subtitle,
                hasRange: !!range,
                range,
                featured: i.featured === true,
                hasDescription: !!i.description,
                selected,
                rowClass: selected ? 'preview-row' : 'preview-row is-deselected'
            };
        });
    }

    get selectedCount() {
        if (!this.hasItems) {
            return 0;
        }
        return this.items.reduce((n, _item, idx) => n + (this.isSelected(idx) ? 1 : 0), 0);
    }

    get allSelected() {
        return this.hasItems && this.selectedCount === this.itemCount;
    }

    get createDisabled() {
        return this.busy || this.selectedCount === 0;
    }

    get createLabel() {
        return `Create ${this.selectedCount} record(s)`;
    }

    get selectionSummary() {
        return `${this.selectedCount} of ${this.itemCount} selected`;
    }

    isSelected(idx) {
        return this.selection[idx] !== false;
    }

    handleResumeChange(event) {
        this.resumeText = event.target.value;
    }

    handleModelChange(event) {
        this.selectedModel = event.detail.value;
    }

    handleIncludeChange(event) {
        this.includeResume = event.target.checked;
    }

    async handleGenerate() {
        this.generating = true;
        this.items = undefined;
        this.selection = [];
        this.createdCount = undefined;
        try {
            const res = await generateFromResume({
                resumeText: this.resumeText,
                modelName: this.selectedModel
            });
            this.items = res || [];
            this.selection = this.items.map(() => true);
            if (!this.items.length) {
                this.toast(
                    'Nothing found',
                    'The assistant did not find any items. Add more detail and try again.',
                    'warning'
                );
            }
        } catch (error) {
            this.toast('Generation failed', this.message(error), 'error');
        } finally {
            this.generating = false;
        }
    }

    handleToggleItem(event) {
        const idx = Number(event.target.dataset.index);
        const checked = event.target.checked;
        this.selection = (this.items ?? []).map((_item, i) =>
            (i === idx ? checked : this.isSelected(i))
        );
    }

    handleToggleAll(event) {
        const checked = event.target.checked;
        this.selection = (this.items ?? []).map(() => checked);
    }

    async handleCreate() {
        const chosen = (this.items ?? []).filter((_item, idx) => this.isSelected(idx));
        if (!chosen.length) {
            this.toast('Nothing selected', 'Select at least one item to create.', 'warning');
            return;
        }
        this.creating = true;
        try {
            const count = await createRecords({
                itemsJson: JSON.stringify(chosen),
                resumeText: this.includeResume ? this.resumeText : null,
                includeResumeRecord: this.includeResume
            });
            this.createdCount = count;
            this.items = undefined;
            this.selection = [];
            this.resumeText = '';
            this.toast(
                'Portfolio saved',
                `${count} record(s) saved (new and updated). Open your site to see them.`,
                'success'
            );
        } catch (error) {
            this.toast('Create failed', this.message(error), 'error');
        } finally {
            this.creating = false;
        }
    }

    handleReset() {
        this.items = undefined;
        this.selection = [];
        this.createdCount = undefined;
    }

    formatRange(start, end) {
        const s = this.formatMonthYear(start);
        if (!s && !end) {
            return '';
        }
        const e = end ? this.formatMonthYear(end) : 'Present';
        return s ? `${s} \u2013 ${e}` : e;
    }

    formatMonthYear(value) {
        if (!value) {
            return '';
        }
        const parts = String(value).split('-');
        if (parts.length < 2) {
            return '';
        }
        const year = Number(parts[0]);
        const month = Number(parts[1]);
        if (!year || !month || month < 1 || month > 12) {
            return '';
        }
        return `${MONTHS[month - 1]} ${year}`;
    }

    message(error) {
        return error?.body?.message || error?.message || 'Unexpected error.';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}