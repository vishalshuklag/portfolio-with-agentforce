import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import listItems from '@salesforce/apex/PortfolioContentAssistant.listItems';
import saveItem from '@salesforce/apex/PortfolioContentAssistant.saveItem';
import deleteItem from '@salesforce/apex/PortfolioContentAssistant.deleteItem';
import generateText from '@salesforce/apex/PortfolioContentAssistant.generateText';
import previewPrompt from '@salesforce/apex/PortfolioContentAssistant.previewPrompt';
import generateFromPrompt from '@salesforce/apex/PortfolioContentAssistant.generateFromPrompt';

const FIELD_DESCRIPTION = 'Description__c';
const FIELD_RESUME = 'Resume_Details__c';

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

const TYPE_OPTIONS = [
    'Bio',
    'Resume',
    'Project',
    'Experience',
    'Education',
    'Certification',
    'YouTube',
    'Blog',
    'Publication',
    'White Paper',
    'Talk',
    'LinkedIn',
    'GitHub',
    'Website',
    'Skill'
].map((t) => ({ label: t, value: t }));

const OTHER = '__other__';

function emptyDraft() {
    return {
        id: null,
        name: '',
        subtitle: '',
        type: '',
        customType: '',
        url: '',
        secondaryUrl: '',
        imageUrl: '',
        description: '',
        resumeDetails: '',
        techStack: '',
        startDate: null,
        endDate: null,
        featured: false,
        active: true,
        sortOrder: null
    };
}

export default class PortfolioItemAssistant extends LightningElement {
    @api modelName = 'sfdc_ai__DefaultOpenAIGPT4OmniMini';

    items;
    error;
    wiredItems;
    _selectedModel;

    showEditor = false;
    isNew = false;
    draft = emptyDraft();

    descInstruction = '';
    resumeInstruction = '';

    isSaving = false;
    generatingField = '';
    pendingDelete;
    isDeleting = false;

    previewingField = '';
    descPrompt = '';
    resumePrompt = '';
    showDescPrompt = false;
    showResumePrompt = false;
    _syncField = '';

    @wire(listItems)
    wiredList(result) {
        this.wiredItems = result;
        if (result.data) {
            this.items = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
        }
    }

    // Push a freshly built prompt into the (uncontrolled) textarea once it renders.
    renderedCallback() {
        if (!this._syncField) {
            return;
        }
        const el = this.promptEditor(this._syncField);
        if (el) {
            el.value = this.promptValue(this._syncField);
            this._syncField = '';
        }
    }

    get loading() {
        return this.items === undefined && !this.error;
    }

    get hasItems() {
        return Array.isArray(this.items) && this.items.length > 0;
    }

    get showEmpty() {
        return !this.loading && !this.error && !this.hasItems;
    }

    get itemCount() {
        return this.hasItems ? this.items.length : 0;
    }

    get decoratedItems() {
        if (!this.hasItems) {
            return [];
        }
        return this.items.map((i) => ({
            ...i,
            statusClass: i.active
                ? 'status-pill status-pill--active'
                : 'status-pill status-pill--inactive',
            statusLabel: i.active ? 'Active' : 'Hidden',
            hasUrl: !!i.url,
            hasSubtitle: !!i.subtitle
        }));
    }

    get typeOptions() {
        return [...TYPE_OPTIONS, { label: 'Other…', value: OTHER }];
    }

    get modelOptions() {
        if (MODEL_OPTIONS.some((o) => o.value === this.modelName)) {
            return MODEL_OPTIONS;
        }
        return [{ label: this.modelName, value: this.modelName }, ...MODEL_OPTIONS];
    }

    get selectedModel() {
        return this._selectedModel || this.modelName;
    }

    get showCustomType() {
        return this.draft.type === OTHER;
    }

    get editorTitle() {
        return this.isNew ? 'New portfolio item' : 'Edit portfolio item';
    }

    get busy() {
        return this.isSaving || !!this.generatingField || !!this.previewingField;
    }

    get generatingDescription() {
        return this.generatingField === FIELD_DESCRIPTION;
    }

    get generatingResume() {
        return this.generatingField === FIELD_RESUME;
    }

    get previewingDescription() {
        return this.previewingField === FIELD_DESCRIPTION;
    }

    get previewingResume() {
        return this.previewingField === FIELD_RESUME;
    }

    get selectedModelLabel() {
        const match = this.modelOptions.find((o) => o.value === this.selectedModel);
        return match ? match.label : this.selectedModel;
    }

    get descGenerateLabel() {
        return this.showDescPrompt ? 'Generate from prompt' : 'Generate';
    }

    get resumeGenerateLabel() {
        return this.showResumePrompt ? 'Generate from prompt' : 'Generate';
    }

    get hasPendingDelete() {
        return !!this.pendingDelete;
    }

    get pendingDeleteName() {
        return this.pendingDelete ? this.pendingDelete.name : '';
    }

    // ---- Type-aware field visibility ----
    get category() {
        return this.classify(this.resolvedType());
    }

    get showImage() {
        return !['linkedin', 'github', 'website', 'resume', 'link'].includes(this.category);
    }

    get showSecondary() {
        return ['project', 'writing', 'video'].includes(this.category);
    }

    get showDates() {
        return ['experience', 'education', 'project', 'certification'].includes(this.category);
    }

    get showTags() {
        return ['project', 'experience', 'writing', 'bio'].includes(this.category);
    }

    get showFeatured() {
        return this.category !== 'resume';
    }

    classify(type) {
        const t = (type || '').toLowerCase();
        if (t.includes('youtube') || t.includes('video')) return 'video';
        if (t.includes('linkedin')) return 'linkedin';
        if (t.includes('github')) return 'github';
        if (t.includes('resume') || t.includes('cv')) return 'resume';
        if (t.includes('bio') || t.includes('about')) return 'bio';
        if (t.includes('project')) return 'project';
        if (t.includes('experience') || t.includes('work') || t.includes('role') || t.includes('job')) {
            return 'experience';
        }
        if (t.includes('education') || t.includes('degree') || t.includes('school') || t.includes('university')) {
            return 'education';
        }
        if (t.includes('cert')) return 'certification';
        if (t.includes('website') || t.includes('site')) return 'website';
        if (
            t.includes('blog') ||
            t.includes('publication') ||
            t.includes('article') ||
            t.includes('paper') ||
            t.includes('writing') ||
            t.includes('talk')
        ) {
            return 'writing';
        }
        return 'link';
    }

    // ---- List actions ----
    handleNew() {
        this.draft = emptyDraft();
        this.isNew = true;
        this.descInstruction = '';
        this.resumeInstruction = '';
        this.resetPreviews();
        this.showEditor = true;
    }

    handleEdit(event) {
        const id = event.currentTarget.dataset.id;
        const record = this.items.find((i) => i.id === id);
        if (!record) {
            return;
        }
        const known = TYPE_OPTIONS.some((o) => o.value === record.type);
        this.draft = {
            id: record.id,
            name: record.name || '',
            subtitle: record.subtitle || '',
            type: known ? record.type : OTHER,
            customType: known ? '' : record.type || '',
            url: record.url || '',
            secondaryUrl: record.secondaryUrl || '',
            imageUrl: record.imageUrl || '',
            description: record.description || '',
            resumeDetails: record.resumeDetails || '',
            techStack: record.techStack || '',
            startDate: record.startDate || null,
            endDate: record.endDate || null,
            featured: !!record.featured,
            active: !!record.active,
            sortOrder: record.sortOrder
        };
        this.isNew = false;
        this.descInstruction = '';
        this.resumeInstruction = '';
        this.resetPreviews();
        this.showEditor = true;
    }

    handleCloseEditor() {
        this.showEditor = false;
    }

    // ---- Editor field changes ----
    handleNameChange(event) {
        this.draft = { ...this.draft, name: event.target.value };
    }
    handleSubtitleChange(event) {
        this.draft = { ...this.draft, subtitle: event.target.value };
    }
    handleTypeChange(event) {
        this.draft = { ...this.draft, type: event.detail.value };
    }
    handleCustomTypeChange(event) {
        this.draft = { ...this.draft, customType: event.target.value };
    }
    handleUrlChange(event) {
        this.draft = { ...this.draft, url: event.target.value };
    }
    handleSecondaryUrlChange(event) {
        this.draft = { ...this.draft, secondaryUrl: event.target.value };
    }
    handleImageUrlChange(event) {
        this.draft = { ...this.draft, imageUrl: event.target.value };
    }
    handleTechStackChange(event) {
        this.draft = { ...this.draft, techStack: event.target.value };
    }
    handleStartDateChange(event) {
        this.draft = { ...this.draft, startDate: event.target.value || null };
    }
    handleEndDateChange(event) {
        this.draft = { ...this.draft, endDate: event.target.value || null };
    }
    handleFeaturedChange(event) {
        this.draft = { ...this.draft, featured: event.target.checked };
    }
    handleSortChange(event) {
        this.draft = { ...this.draft, sortOrder: event.target.value };
    }
    handleActiveChange(event) {
        this.draft = { ...this.draft, active: event.target.checked };
    }
    handleDescriptionChange(event) {
        this.draft = { ...this.draft, description: event.target.value };
    }
    handleResumeChange(event) {
        this.draft = { ...this.draft, resumeDetails: event.target.value };
    }
    handleDescInstruction(event) {
        this.descInstruction = event.target.value;
    }
    handleResumeInstruction(event) {
        this.resumeInstruction = event.target.value;
    }
    handleDescPromptEdit(event) {
        this.descPrompt = event.target.value;
    }
    handleResumePromptEdit(event) {
        this.resumePrompt = event.target.value;
    }
    handleModelChange(event) {
        this._selectedModel = event.detail.value;
    }

    resolvedType() {
        return this.draft.type === OTHER ? this.draft.customType : this.draft.type;
    }

    // ---- AI generation ----
    async generateFor(targetField, existing, instruction) {
        this.generatingField = targetField;
        try {
            const text = await generateText({
                title: this.draft.name,
                type: this.resolvedType(),
                url: this.draft.url,
                targetField,
                existing,
                instruction,
                modelName: this.selectedModel
            });
            if (targetField === FIELD_RESUME) {
                const html = (text || '').replace(/\n/g, '<br/>');
                this.draft = { ...this.draft, resumeDetails: html };
            } else {
                this.draft = { ...this.draft, description: text };
            }
            this.resetPreviews();
        } catch (error) {
            this.toast('Generation failed', this.message(error), 'error');
        } finally {
            this.generatingField = '';
        }
    }

    handleGenerateDescription() {
        if (this.showDescPrompt) {
            this.generateFromEdited(FIELD_DESCRIPTION, this.descPrompt);
        } else {
            this.generateFor(FIELD_DESCRIPTION, this.draft.description, this.descInstruction);
        }
    }

    handleGenerateResume() {
        if (this.showResumePrompt) {
            this.generateFromEdited(FIELD_RESUME, this.resumePrompt);
        } else {
            this.generateFor(FIELD_RESUME, this.draft.resumeDetails, this.resumeInstruction);
        }
    }

    // Sends the previewed (and possibly hand-edited) prompt verbatim.
    async generateFromEdited(targetField, prompt) {
        if (!prompt || !prompt.trim()) {
            this.toast(
                'Empty prompt',
                'The prompt is empty. Edit it or click Preview prompt to rebuild from the fields.',
                'warning'
            );
            return;
        }
        this.generatingField = targetField;
        try {
            const text = await generateFromPrompt({
                prompt,
                modelName: this.selectedModel
            });
            if (targetField === FIELD_RESUME) {
                const html = (text || '').replace(/\n/g, '<br/>');
                this.draft = { ...this.draft, resumeDetails: html };
            } else {
                this.draft = { ...this.draft, description: text };
            }
            this.resetPreviews();
        } catch (error) {
            this.toast('Generation failed', this.message(error), 'error');
        } finally {
            this.generatingField = '';
        }
    }

    // ---- Prompt preview (verify before generating) ----
    async previewFor(targetField, existing, instruction) {
        this.previewingField = targetField;
        try {
            const prompt = await previewPrompt({
                title: this.draft.name,
                type: this.resolvedType(),
                url: this.draft.url,
                targetField,
                existing,
                instruction
            });
            if (targetField === FIELD_RESUME) {
                this.resumePrompt = prompt;
                this.showResumePrompt = true;
            } else {
                this.descPrompt = prompt;
                this.showDescPrompt = true;
            }
            this.syncPromptToDom(targetField);
        } catch (error) {
            this.toast('Preview failed', this.message(error), 'error');
        } finally {
            this.previewingField = '';
        }
    }

    // The prompt textarea is uncontrolled (no value binding) to preserve the
    // caret while typing, so set its value here when the prompt is (re)built.
    syncPromptToDom(targetField) {
        const el = this.promptEditor(targetField);
        if (el) {
            el.value = this.promptValue(targetField);
        } else {
            this._syncField = targetField;
        }
    }

    promptEditor(targetField) {
        const dataField = targetField === FIELD_RESUME ? 'resume' : 'desc';
        return this.template.querySelector(
            `.prompt-preview__editor[data-field="${dataField}"]`
        );
    }

    promptValue(targetField) {
        return targetField === FIELD_RESUME ? this.resumePrompt : this.descPrompt;
    }

    handlePreviewDescription() {
        this.previewFor(FIELD_DESCRIPTION, this.draft.description, this.descInstruction);
    }

    handlePreviewResume() {
        this.previewFor(FIELD_RESUME, this.draft.resumeDetails, this.resumeInstruction);
    }

    handleHideDescPrompt() {
        this.showDescPrompt = false;
    }

    handleHideResumePrompt() {
        this.showResumePrompt = false;
    }

    handleCopyDescPrompt() {
        this.copyText(this.descPrompt);
    }

    handleCopyResumePrompt() {
        this.copyText(this.resumePrompt);
    }

    copyText(text) {
        if (!text) {
            return;
        }
        try {
            navigator.clipboard.writeText(text);
            this.toast('Copied', 'Prompt copied to clipboard.', 'success');
        } catch (e) {
            this.toast('Copy failed', 'Select the text and copy it manually.', 'warning');
        }
    }

    resetPreviews() {
        this.showDescPrompt = false;
        this.showResumePrompt = false;
        this.descPrompt = '';
        this.resumePrompt = '';
    }

    // ---- Save ----
    async handleSave() {
        const type = this.resolvedType();
        if (!this.draft.name || !this.draft.name.trim()) {
            this.toast('Missing title', 'Please enter a title.', 'warning');
            return;
        }
        if (!type || !type.trim()) {
            this.toast('Missing type', 'Please choose or enter a type.', 'warning');
            return;
        }
        this.isSaving = true;
        try {
            await saveItem({
                itemJson: JSON.stringify({
                    id: this.draft.id,
                    name: this.draft.name,
                    subtitle: this.draft.subtitle,
                    type,
                    url: this.draft.url,
                    secondaryUrl: this.draft.secondaryUrl,
                    imageUrl: this.draft.imageUrl,
                    description: this.draft.description,
                    resumeDetails: this.draft.resumeDetails,
                    techStack: this.draft.techStack,
                    startDate: this.draft.startDate || null,
                    endDate: this.draft.endDate || null,
                    featured: !!this.draft.featured,
                    active: this.draft.active,
                    sortOrder: this.draft.sortOrder ? Number(this.draft.sortOrder) : null
                })
            });
            this.toast('Saved', `"${this.draft.name}" was saved.`, 'success');
            this.showEditor = false;
            await refreshApex(this.wiredItems);
        } catch (error) {
            this.toast('Save failed', this.message(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // ---- Delete ----
    handleAskDelete(event) {
        const id = event.currentTarget.dataset.id;
        this.pendingDelete = this.items.find((i) => i.id === id);
    }

    handleCancelDelete() {
        this.pendingDelete = undefined;
    }

    async handleConfirmDelete() {
        if (!this.pendingDelete) {
            return;
        }
        this.isDeleting = true;
        const name = this.pendingDelete.name;
        try {
            await deleteItem({ recordId: this.pendingDelete.id });
            this.toast('Deleted', `"${name}" was deleted.`, 'success');
            this.pendingDelete = undefined;
            await refreshApex(this.wiredItems);
        } catch (error) {
            this.toast('Delete failed', this.message(error), 'error');
        } finally {
            this.isDeleting = false;
        }
    }

    // ---- utils ----
    message(error) {
        return error?.body?.message || error?.message || 'Unexpected error.';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}