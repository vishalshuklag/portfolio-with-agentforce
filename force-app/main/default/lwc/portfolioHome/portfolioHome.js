import { LightningElement, api, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import getPortfolioItems from '@salesforce/apex/PortfolioPublicController.getPortfolioItems';
import generatePdfBase64 from '@salesforce/apex/PortfolioPdfController.generatePdfBase64';
import PORTFOLIO_BRIDGE from '@salesforce/resourceUrl/portfolioBridge';
import ESW_ORG_ID from '@salesforce/label/c.Portfolio_ESW_Org_Id';
import ESW_DEPLOYMENT from '@salesforce/label/c.Portfolio_ESW_Deployment';
import ESW_SITE_URL from '@salesforce/label/c.Portfolio_ESW_Site_Url';
import ESW_SCRT2_URL from '@salesforce/label/c.Portfolio_ESW_Scrt2_Url';

// Embedded Messaging (Agentforce Service Agent) is loaded by this component itself
// — not via the site's page context — so it lives in the same Lightning Web Security
// sandbox as the buttons below and can be launched with a direct API call.
// Org-specific values come from Custom Labels (Setup → Custom Labels → Portfolio ESW *).
const ESW_BOOTSTRAP_URL = `${ESW_SITE_URL}/assets/js/bootstrap.min.js`;

const CATEGORY_META = {
    bio: { label: 'About', icon: 'utility:user', accent: 'indigo', cta: 'Learn more' },
    project: { label: 'Projects', icon: 'utility:apps', accent: 'indigo', cta: 'View project' },
    experience: { label: 'Experience', icon: 'utility:work_order_type', accent: 'teal', cta: 'Learn more' },
    education: { label: 'Education', icon: 'utility:education', accent: 'teal', cta: 'Learn more' },
    video: { label: 'Videos', icon: 'utility:video', accent: 'red', cta: 'Watch on YouTube' },
    writing: { label: 'Writing', icon: 'utility:knowledge_base', accent: 'green', cta: 'Read article' },
    resume: { label: 'Resume', icon: 'utility:download', accent: 'purple', cta: 'View resume' },
    certification: { label: 'Certifications', icon: 'utility:trophy', accent: 'gold', cta: 'View credential' },
    award: { label: 'Award', icon: 'utility:favorite', accent: 'gold', cta: 'Learn more' },
    skill: { label: 'Skill', icon: 'utility:apps', accent: 'indigo', cta: 'Learn more' },
    aitool: { label: 'AI', icon: 'utility:einstein', accent: 'indigo', cta: 'Learn more' },
    endorsement: { label: 'Endorsement', icon: 'utility:chat', accent: 'teal', cta: 'Learn more' },
    service: { label: 'Service', icon: 'utility:work_order_type', accent: 'green', cta: 'Learn more' },
    now: { label: 'Currently', icon: 'utility:clock', accent: 'indigo', cta: 'Learn more' },
    language: { label: 'Language', icon: 'utility:world', accent: 'teal', cta: 'Learn more' },
    community: { label: 'Community', icon: 'utility:groups', accent: 'teal', cta: 'Learn more' },
    volunteering: { label: 'Volunteering', icon: 'utility:heart', accent: 'green', cta: 'Learn more' },
    interest: { label: 'Interest', icon: 'utility:like', accent: 'purple', cta: 'Learn more' },
    linkedin: { label: 'LinkedIn', icon: 'utility:company', accent: 'blue', cta: 'View profile' },
    github: { label: 'GitHub', icon: 'utility:link', accent: 'slate', cta: 'View code' },
    website: { label: 'Website', icon: 'utility:world', accent: 'indigo', cta: 'Open link' },
    link: { label: 'Links', icon: 'utility:world', accent: 'indigo', cta: 'Open link' },
    other: { label: 'More', icon: 'utility:apps', accent: 'slate', cta: 'Open link' }
};

const MONTHS = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

export default class PortfolioHome extends LightningElement {
    @api ownerName = 'Vishal Shukla';
    @api roleTitle;
    @api headline;
    @api subheadline =
        'Ask the AI assistant anything about my background, experience, and work — or explore the highlights below.';
    @api avatarUrl;
    @api location;
    @api showItems = false;

    items;
    error;
    activeVideoId;
    pdfBusy = false;

    @wire(getPortfolioItems)
    wiredItems({ data, error }) {
        if (data) {
            this.items = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.items = undefined;
        }
    }

    connectedCallback() {
        // Preload the page-context bridge so the PDF download works under LWS.
        this.ensureBridge();
        // Load + initialize Embedded Messaging inside this component so the Ask AI
        // buttons can launch it directly (same LWS sandbox as this component).
        this.ensureEsw();
        console.log({ESW_BOOTSTRAP_URL});
        
    }

    ensureBridge() {
        if (!this._bridgePromise) {
            this._bridgePromise = loadScript(this, PORTFOLIO_BRIDGE).catch((error) => {
                this._bridgePromise = null;
                console.error(`Something went wrong:: ensureBridge()`, error);
                
            });
        }
        return this._bridgePromise || Promise.resolve();
    }

    ensureEsw() {
        console.log(`ensureEsw invoked::`);
        
        if (!this._eswPromise) {
            this._eswPromise = loadScript(this, ESW_BOOTSTRAP_URL)
                .then(() => this.initEsw())
                .catch((e) => {
                    this._eswPromise = null;
                    // eslint-disable-next-line no-console
                    console.error('Error loading Embedded Messaging:', e);
                });
        }
        return this._eswPromise || Promise.resolve();
    }

    initEsw() {
        const esw = window.embeddedservice_bootstrap;
        if (!esw || this._eswInited) {
            return;
        }
        this._eswInited = true;
        try {
            esw.settings.language = 'en_US';
        } catch (e) {
            console.error(`Something went wrong:: initEsw()`, e);
            
            /* keep default language */
        }
        esw.init(ESW_ORG_ID, ESW_DEPLOYMENT, ESW_SITE_URL, { scrt2URL: ESW_SCRT2_URL });
    }

    // ---------- Hero ----------
    get computedHeadline() {
        return this.headline || `Hi, I'm ${this.ownerName}`;
    }

    get computedRole() {
        return this.roleTitle || 'Portfolio';
    }

    get loading() {
        return this.items === undefined && !this.error;
    }

    get hasError() {
        return !!this.error;
    }

    get hasItems() {
        return Array.isArray(this.items) && this.items.length > 0;
    }

    get hasAvatar() {
        return !!this.avatarUrl;
    }

    get hasLocation() {
        return !!this.location;
    }

    get initials() {
        const name = (this.ownerName || '').trim();
        if (!name || name === 'the owner') {
            return '\u2605';
        }
        const parts = name.split(/\s+/).filter(Boolean);
        const first = parts[0] ? parts[0][0] : '';
        const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
        return (first + last).toUpperCase();
    }

    // ---------- Social + resume ----------
    get socialLinks() {
        if (!this.hasItems) {
            return [];
        }
        return this.items
            .filter((i) => {
                const cat = this.classify(i.type);
                return i.url && (cat === 'linkedin' || cat === 'github' || cat === 'website');
            })
            .map((i) => {
                const meta = CATEGORY_META[this.classify(i.type)];
                return { id: i.id, url: i.url, iconName: meta.icon, label: meta.label };
            });
    }

    get hasSocials() {
        return this.socialLinks.length > 0;
    }

    get resumeLink() {
        if (!this.hasItems) {
            return null;
        }
        const resume = this.items.find((i) => this.classify(i.type) === 'resume' && i.url);
        return resume ? resume.url : null;
    }

    get hasResume() {
        return !!this.resumeLink;
    }

    // ---------- Section: About ----------
    get aboutItems() {
        return this.sectionItems('bio', false).map((i) => this.decorate(i));
    }

    get hasAbout() {
        return this.aboutItems.length > 0;
    }

    get aboutLead() {
        return this.hasAbout ? this.aboutItems[0] : null;
    }

    // ---------- Section: Featured ----------
    get featuredItems() {
        if (!this.hasItems) {
            return [];
        }
        return this.items
            .filter((i) => i.featured && this.classify(i.type) !== 'resume')
            .map((i) => this.decorate(i));
    }

    get hasFeatured() {
        return this.featuredItems.length > 0;
    }

    // ---------- Section: Projects ----------
    get projectItems() {
        return this.sectionItems('project', true).map((i) => this.decorate(i));
    }

    get hasProjects() {
        return this.projectItems.length > 0;
    }

    // ---------- Section: Experience timeline ----------
    get experienceItems() {
        return this.timelineFor('experience');
    }

    get hasExperience() {
        return this.experienceItems.length > 0;
    }

    // ---------- Section: Education timeline ----------
    get educationItems() {
        return this.timelineFor('education');
    }

    get hasEducation() {
        return this.educationItems.length > 0;
    }

    timelineFor(category) {
        if (!this.hasItems) {
            return [];
        }
        return this.items
            .filter((i) => !i.featured && this.classify(i.type) === category)
            .sort((a, b) => this.sortDateDesc(a, b))
            .map((i) => this.decorate(i));
    }

    // ---------- Section: Certifications ----------
    get certItems() {
        return this.sectionItems('certification', true).map((i) => this.decorate(i));
    }

    get hasCerts() {
        return this.certItems.length > 0;
    }

    // ---------- Section: Writing ----------
    get writingItems() {
        return this.sectionItems('writing', true).map((i) => this.decorate(i));
    }

    get hasWriting() {
        return this.writingItems.length > 0;
    }

    // ---------- Section: Videos ----------
    get videoItems() {
        return this.sectionItems('video', true).map((i) => this.decorate(i));
    }

    get hasVideos() {
        return this.videoItems.length > 0;
    }

    // ---------- Section: Profiles / links ----------
    get linkItems() {
        if (!this.hasItems) {
            return [];
        }
        return this.items
            .filter((i) => {
                if (i.featured) {
                    return false;
                }
                const cat = this.classify(i.type);
                return cat === 'linkedin' || cat === 'github' || cat === 'website' || cat === 'link';
            })
            .map((i) => this.decorate(i));
    }

    get hasLinks() {
        return this.linkItems.length > 0;
    }

    // ---------- Section: Awards & recognition ----------
    get awardItems() {
        return this.sectionItems('award', true).map((i) => this.decorate(i));
    }

    get hasAwards() {
        return this.awardItems.length > 0;
    }

    // ---------- Section: Community contributions ----------
    get communityItems() {
        return this.sectionItems('community', true).map((i) => this.decorate(i));
    }

    get hasCommunity() {
        return this.communityItems.length > 0;
    }

    // ---------- Section: Volunteering ----------
    get volunteerItems() {
        return this.sectionItems('volunteering', true).map((i) => this.decorate(i));
    }

    get hasVolunteer() {
        return this.volunteerItems.length > 0;
    }

    // ---------- Section: Interests ----------
    get interestItems() {
        return this.sectionItems('interest', true).map((i) => this.decorate(i));
    }

    get hasInterests() {
        return this.interestItems.length > 0;
    }

    // ---------- Section: Skills (grouped by category) ----------
    get skillGroups() {
        if (!this.hasItems) {
            return [];
        }
        const byCategory = new Map();
        this.items.forEach((i) => {
            if (this.classify(i.type) !== 'skill') {
                return;
            }
            const category = i.subtitle && i.subtitle.trim() ? i.subtitle.trim() : 'General';
            if (!byCategory.has(category)) {
                byCategory.set(category, []);
            }
            const skills = byCategory.get(category);
            skills.push({ key: i.id, label: i.title });
            if (i.techStack) {
                i.techStack.split(',').forEach((t, idx) => {
                    const label = t.trim();
                    if (label) {
                        skills.push({ key: `${i.id}-t${idx}`, label });
                    }
                });
            }
        });
        return Array.from(byCategory.entries()).map(([category, skills]) => ({
            key: category,
            category,
            skills
        }));
    }

    get hasSkills() {
        return this.skillGroups.length > 0;
    }

    // ---------- Section: AI usage (tools & workflow) ----------
    get aiToolItems() {
        return this.sectionItems('aitool', false).map((i) => this.decorate(i));
    }

    get hasAiTools() {
        return this.aiToolItems.length > 0;
    }

    // ---------- Section: Endorsements (testimonials) ----------
    get endorsementItems() {
        return this.sectionItems('endorsement', false).map((i) => {
            const d = this.decorate(i);
            return { ...d, initials: this.initialsOf(d.title) };
        });
    }

    get hasEndorsements() {
        return this.endorsementItems.length > 0;
    }

    // ---------- Section: Services ----------
    get serviceItems() {
        return this.sectionItems('service', false).map((i) => this.decorate(i));
    }

    get hasServices() {
        return this.serviceItems.length > 0;
    }

    // ---------- Section: Currently / Now ----------
    get nowItem() {
        const items = this.sectionItems('now', false);
        return items.length ? this.decorate(items[0]) : null;
    }

    get hasNow() {
        return !!this.nowItem;
    }

    // ---------- Section: Languages ----------
    get languageItems() {
        return this.sectionItems('language', false).map((i) => this.decorate(i));
    }

    get hasLanguages() {
        return this.languageItems.length > 0;
    }

    // ---------- Section: By the numbers (computed stats) ----------
    get stats() {
        if (!this.hasItems) {
            return [];
        }
        const tiles = [];
        const years = this.yearsOfExperience;
        if (years) {
            tiles.push({ key: 'yrs', value: `${years}+`, label: 'Years experience' });
        }
        const certs = this.countByCategory('certification');
        if (certs) {
            tiles.push({ key: 'certs', value: `${certs}`, label: 'Certifications' });
        }
        const projects = this.countByCategory('project');
        if (projects) {
            tiles.push({ key: 'projects', value: `${projects}`, label: 'Projects' });
        }
        const awards = this.countByCategory('award');
        if (awards) {
            tiles.push({ key: 'awards', value: `${awards}`, label: 'Awards' });
        }
        return tiles;
    }

    get hasStats() {
        return this.stats.length >= 2;
    }

    get yearsOfExperience() {
        if (!this.hasItems) {
            return null;
        }
        let earliest = null;
        this.items.forEach((i) => {
            if (this.classify(i.type) === 'experience' && i.startDate) {
                if (!earliest || i.startDate < earliest) {
                    earliest = i.startDate;
                }
            }
        });
        if (!earliest) {
            return null;
        }
        const start = new Date(earliest);
        const now = new Date();
        let years = now.getFullYear() - start.getFullYear();
        const monthDelta = now.getMonth() - start.getMonth();
        if (monthDelta < 0 || (monthDelta === 0 && now.getDate() < start.getDate())) {
            years -= 1;
        }
        return years > 0 ? years : null;
    }

    countByCategory(category) {
        if (!this.hasItems) {
            return 0;
        }
        return this.items.filter((i) => this.classify(i.type) === category).length;
    }

    initialsOf(name) {
        const n = (name || '').trim();
        if (!n) {
            return '\u201C';
        }
        const parts = n.split(/\s+/).filter(Boolean);
        const first = parts[0] ? parts[0][0] : '';
        const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
        return (first + last).toUpperCase();
    }

    // ---------- Section: More (everything not covered above) ----------
    // True catch-all: any active item that none of the dedicated sections (or the
    // resume button / hero) already render, so nothing the owner adds is ever lost.
    get otherItems() {
        if (!this.hasItems) {
            return [];
        }
        // Every category that a dedicated section (or the resume button / hero)
        // already renders. Anything else falls through to the "More" section so
        // nothing the owner adds is ever lost. Featured items are shown in the
        // Featured section regardless of category, so they're excluded too.
        const handled = new Set([
            'bio', 'project', 'experience', 'education', 'certification', 'award',
            'skill', 'aitool', 'endorsement', 'service', 'now', 'language',
            'community', 'volunteering', 'writing', 'video',
            'linkedin', 'github', 'website', 'link', 'interest', 'resume'
        ]);
        return this.items
            .filter((i) => !i.featured && !handled.has(this.classify(i.type)))
            .map((i) => this.decorate(i));
    }

    get hasOther() {
        return this.otherItems.length > 0;
    }

    // ---------- Nav ----------
    get navItems() {
        const nav = [];
        if (!this.showSections) {
            return nav;
        }
        if (this.hasAbout) nav.push({ key: 'about', label: 'About', target: 'about' });
        if (this.hasSkills) nav.push({ key: 'skills', label: 'Skills', target: 'skills' });
        if (this.hasFeatured || this.hasProjects) nav.push({ key: 'work', label: 'Work', target: 'work' });
        if (this.hasExperience || this.hasEducation) {
            nav.push({ key: 'experience', label: 'Experience', target: 'experience' });
        }
        if (this.hasCommunity || this.hasAwards || this.hasVolunteer || this.hasEndorsements) {
            nav.push({ key: 'community', label: 'Community', target: 'community' });
        }
        if (this.hasWriting || this.hasVideos) nav.push({ key: 'content', label: 'Content', target: 'content' });
        nav.push({ key: 'contact', label: 'Contact', target: 'contact' });
        return nav;
    }

    get showSections() {
        return this.showItems && this.hasItems;
    }

    // ---------- Helpers ----------
    sectionItems(category, excludeFeatured) {
        if (!this.hasItems) {
            return [];
        }
        return this.items.filter((i) => {
            if (excludeFeatured && i.featured) {
                return false;
            }
            return this.classify(i.type) === category;
        });
    }

    classify(type) {
        const t = (type || '').toLowerCase();
        if (!t) return 'other';
        if (t.includes('youtube') || t.includes('video')) return 'video';
        if (t.includes('linkedin')) return 'linkedin';
        if (t.includes('github')) return 'github';
        if (t.includes('resume') || t.includes('cv')) return 'resume';
        if (t.includes('bio') || t.includes('about')) return 'bio';
        if (
            t.includes('endorsement') ||
            t.includes('testimonial') ||
            t.includes('recommendation')
        ) {
            return 'endorsement';
        }
        if (t === 'ai' || t.includes('ai tool') || t.includes('ai usage') || t.includes('ai/ml') || t.includes('genai')) {
            return 'aitool';
        }
        if (t.includes('skill') || t.includes('expertise') || t.includes('competenc')) {
            return 'skill';
        }
        if (t.includes('service') || t.includes('offering')) {
            return 'service';
        }
        if (t === 'now' || t.includes('current') || t.includes('focus')) {
            return 'now';
        }
        if (t.includes('language') || t.includes('spoken')) {
            return 'language';
        }
        if (
            t.includes('award') ||
            t.includes('reward') ||
            t.includes('honor') ||
            t.includes('honour') ||
            t.includes('recognition') ||
            t.includes('prize') ||
            t.includes('accolade')
        ) {
            return 'award';
        }
        if (
            t.includes('volunteer') ||
            t.includes('nonprofit') ||
            t.includes('non-profit') ||
            t.includes('charity') ||
            t.includes('pro bono')
        ) {
            return 'volunteering';
        }
        if (
            t.includes('community') ||
            t.includes('mentor') ||
            t.includes('ambassador') ||
            t.includes('user group') ||
            t.includes('meetup') ||
            t.includes('advocate') ||
            t.includes('mvp')
        ) {
            return 'community';
        }
        if (
            t.includes('interest') ||
            t.includes('hobby') ||
            t.includes('hobbies') ||
            t.includes('passion')
        ) {
            return 'interest';
        }
        if (t.includes('project')) return 'project';
        if (t.includes('experience') || t.includes('work') || t.includes('role') || t.includes('job')) {
            return 'experience';
        }
        if (t.includes('education') || t.includes('degree') || t.includes('school') || t.includes('university')) {
            return 'education';
        }
        if (t.includes('cert')) return 'certification';
        if (t.includes('website') || t.includes('portfolio') || t.includes('site')) return 'website';
        if (
            t.includes('blog') ||
            t.includes('publication') ||
            t.includes('article') ||
            t.includes('paper') ||
            t.includes('writing') ||
            t.includes('talk') ||
            t.includes('podcast')
        ) {
            return 'writing';
        }
        if (t.includes('link') || t.includes('profile')) return 'link';
        return 'other';
    }

    decorate(item) {
        const category = this.classify(item.type);
        const meta = CATEGORY_META[category] || CATEGORY_META.link;
        const url = item.url;
        const youtubeId = this.youtubeId(url) || this.youtubeId(item.secondaryUrl);
        const isVideo = category === 'video' && !!youtubeId;
        const domain = this.domainOf(url);
        const isPlaying = isVideo && this.activeVideoId === item.id;
        const tags = this.parseTags(item.techStack);
        const timeframe = this.formatTimeframe(item.startDate, item.endDate);
        const imageUrl =
            item.imageUrl ||
            (isVideo ? `https://img.youtube.com/vi/${youtubeId}/hqdefault.jpg` : null);

        return {
            id: item.id,
            title: item.title,
            subtitle: item.subtitle,
            description: item.description,
            typeLabel: item.type,
            iconName: meta.icon,
            ctaLabel: meta.cta,
            accentClass: `accent-${meta.accent}`,
            cardClass: `card accent-${meta.accent}`,
            badgeClass: `badge badge-${meta.accent}`,
            hasSubtitle: !!item.subtitle,
            hasDescription: !!item.description,
            hasTimeframe: !!timeframe,
            timeframe,
            hasTags: tags.length > 0,
            tags,
            hasUrl: !!url,
            url,
            hasSecondary: !!item.secondaryUrl,
            secondaryUrl: item.secondaryUrl,
            isVideo,
            youtubeId,
            isPlaying,
            showVideoCta: category === 'video' && !isVideo && !!url,
            hasImage: !!imageUrl,
            imageUrl,
            embedUrl: isVideo
                ? `https://www.youtube-nocookie.com/embed/${youtubeId}?autoplay=1&rel=0`
                : null,
            showLinkPreview: !!url && !isVideo && !!domain,
            domain,
            faviconUrl: domain
                ? `https://www.google.com/s2/favicons?domain=${domain}&sz=64`
                : null
        };
    }

    parseTags(value) {
        if (!value) {
            return [];
        }
        return value
            .split(',')
            .map((t) => t.trim())
            .filter(Boolean)
            .map((label, idx) => ({ key: `${idx}-${label}`, label }));
    }

    formatTimeframe(start, end) {
        const s = this.formatMonthYear(start);
        const e = end ? this.formatMonthYear(end) : 'Present';
        if (!s) {
            return end ? e : '';
        }
        return `${s} \u2013 ${e}`;
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

    sortDateDesc(a, b) {
        const av = a.startDate || a.endDate || '';
        const bv = b.startDate || b.endDate || '';
        if (av === bv) {
            return 0;
        }
        return av < bv ? 1 : -1;
    }

    youtubeId(url) {
        if (!url) {
            return null;
        }
        const patterns = [
            /[?&]v=([a-zA-Z0-9_-]{11})/,
            /youtu\.be\/([a-zA-Z0-9_-]{11})/,
            /youtube\.com\/embed\/([a-zA-Z0-9_-]{11})/,
            /youtube\.com\/shorts\/([a-zA-Z0-9_-]{11})/
        ];
        for (const pattern of patterns) {
            const match = url.match(pattern);
            if (match) {
                return match[1];
            }
        }
        return null;
    }

    domainOf(url) {
        if (!url) {
            return '';
        }
        try {
            return new URL(url).hostname.replace(/^www\./, '');
        } catch (e) {
            return '';
        }
    }

    // ---------- Interactions ----------
    handlePlay(event) {
        this.activeVideoId = event.currentTarget.dataset.id;
    }

    handleNav(event) {
        event.preventDefault();
        this.scrollToTarget(event.currentTarget.dataset.target);
    }

    async handleAskAI() {
        console.log(`Calling ASK AI`);
        
        await this.ensureEsw();
        if (this.tryLaunch()) {
            return;
        }
        // Messaging may still be initializing — retry briefly, then fall back.
        let tries = 0;
        const timer = setInterval(() => {
            tries += 1;
            if (this.tryLaunch()) {
                clearInterval(timer);
            } else if (tries > 30) {
                clearInterval(timer);
                this.scrollToTarget('contact');
            }
        }, 300);
    }

    tryLaunch() {
        try {
            const esw = window.embeddedservice_bootstrap;
            if (esw && esw.utilAPI && typeof esw.utilAPI.launchChat === 'function') {
                esw.utilAPI.launchChat();
                return true;
            }
        } catch (e) {
            /* not ready yet */
        }
        return false;
    }

    async handleDownloadPdf() {
        if (this.pdfBusy) {
            return;
        }
        this.pdfBusy = true;
        try {
            // Generated server-side with Apex Blob.toPdf() (no Visualforce).
            // Pass the hero context so the PDF header mirrors the live site.
            const base64 = await generatePdfBase64({
                ownerOverride:
                    this.ownerName && this.ownerName !== 'the owner' ? this.ownerName : null,
                roleOverride: this.roleTitle || null,
                subheadlineOverride: this.subheadline || null,
                locationOverride: this.location || null
            });
            const filename = `${(this.ownerName || 'portfolio').trim().replace(/\s+/g, '_')}_portfolio.pdf`;
            // Hand the bytes to the page-context bridge to perform the download,
            // since a Blob/anchor download is unreliable from the LWS sandbox.
            await this.ensureBridge();
            window.dispatchEvent(
                new CustomEvent('portfolioDownloadPdf', { detail: { base64, filename } })
            );
        } catch (e) {
            // Could not generate the PDF (e.g. guest lacks Apex access) — fall back
            // to the browser's built-in print / save-as-PDF.
            window.print();
        } finally {
            this.pdfBusy = false;
        }
    }

    handleImageError(event) {
        const img = event.currentTarget;
        const figure = img.closest('.media, .thumb, .cert-badge');
        if (figure) {
            figure.classList.add('media--broken');
        } else {
            img.style.display = 'none';
        }
    }

    scrollToTarget(target) {
        const el = this.template.querySelector(`[data-section="${target}"]`);
        if (el && el.scrollIntoView) {
            el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }
}