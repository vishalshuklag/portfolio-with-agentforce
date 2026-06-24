/**
 * Builds a branded portfolio/resume PDF entirely in Apex using Blob.toPdf(html)
 * (no Visualforce page required). It mirrors the public portfolioHome site: the
 * same classification logic, the same section order, and the same palette/visual
 * language (indigo accent, eyebrow + title section heads, category-coloured
 * badges, tag chips, timelines) so the downloaded PDF reflects what visitors see.
 *
 * Because Blob.toPdf() renders with a CSS 2.1 engine (no flexbox/grid/CSS
 * variables/web fonts), the layout is rebuilt with print-safe primitives
 * (tables, inline-block, floats, explicit colours) rather than the site CSS.
 *
 * The portfolioHome LWC calls generatePdfBase64() and offers the result as a
 * download — this works for guest visitors with only Apex class access.
 */
public with sharing class PortfolioPdfController {
  // ---- Palette (mirrors portfolioHome.css custom properties) ----
  private static final String INK = '#0f172a';
  private static final String INK_SOFT = '#334155';
  private static final String MUTED = '#64748b';
  private static final String BORDER = '#e6e9ef';
  private static final String BORDER_STRONG = '#d4d9e2';
  private static final String ACCENT = '#4f46e5';
  private static final String ACCENT_SOFT = '#eef2ff';
  private static final String SURFACE = '#ffffff';

  public String ownerName { get; private set; }
  public String roleTitle { get; private set; }
  public String tagline { get; private set; }
  public String location { get; private set; }
  public String initials { get; private set; }

  private List<Entry> entries = new List<Entry>();

  public PortfolioPdfController() {
    List<Portfolio_Item__c> records = [
      SELECT
        Id,
        Name,
        Subtitle__c,
        Type__c,
        URL__c,
        Secondary_URL__c,
        Description__c,
        Tech_Stack__c,
        Start_Date__c,
        End_Date__c,
        Is_Featured__c
      FROM Portfolio_Item__c
      WHERE Active__c = TRUE
      ORDER BY
        Is_Featured__c DESC,
        Sort_Order__c ASC NULLS LAST,
        Start_Date__c DESC NULLS LAST,
        Name ASC
      LIMIT 500
    ];

    String bioName;
    String bioSummary;
    for (Portfolio_Item__c p : records) {
      entries.add(new Entry(p));
      if (classify(p.Type__c) == 'bio') {
        if (String.isBlank(bioName)) {
          bioName = p.Name;
        }
        if (String.isBlank(bioSummary)) {
          bioSummary = p.Description__c;
        }
      }
    }
    this.ownerName = String.isNotBlank(bioName) ? bioName : 'My Portfolio';
    this.tagline = bioSummary;
    this.initials = computeInitials(this.ownerName);
  }

  /**
   * Generates the PDF with Apex's native Blob.toPdf() and returns it
   * base64-encoded — no Visualforce page involved. Header context (role,
   * tagline, location) is passed from the LWC so it matches the site hero.
   */
  @AuraEnabled
  public static String generatePdfBase64(
    String ownerOverride,
    String roleOverride,
    String subheadlineOverride,
    String locationOverride
  ) {
    PortfolioPdfController ctrl = new PortfolioPdfController();
    if (String.isNotBlank(ownerOverride)) {
      ctrl.ownerName = ownerOverride;
      ctrl.initials = computeInitials(ownerOverride);
    }
    if (String.isNotBlank(roleOverride)) {
      ctrl.roleTitle = roleOverride;
    }
    if (String.isNotBlank(subheadlineOverride)) {
      ctrl.tagline = subheadlineOverride;
    }
    if (String.isNotBlank(locationOverride)) {
      ctrl.location = locationOverride;
    }
    String html = ctrl.buildHtml();
    Blob body = Test.isRunningTest() ? Blob.valueOf(html) : Blob.toPdf(html);
    return EncodingUtil.base64Encode(body);
  }

  // =====================================================================
  // HTML assembly
  // =====================================================================
  @TestVisible
  private String buildHtml() {
    String s =
      '<html><head><meta charset="UTF-8"/><style>' +
      css() +
      '</style></head><body>';
    s += header();

    // Order mirrors portfolioHome.html.
    s += statsBand();
    s += nowCallout();
    s += aboutSection();
    s += skillsSection();
    s += cardSection('How I work', 'AI usage', byCategory('aitool', false));
    s += cardSection('What I offer', 'Services', byCategory('service', false));
    s += featuredSection();
    s += cardSection('Portfolio', 'Projects', byCategory('project', true));
    s += timelineSection(
      'Background',
      'Experience',
      byCategory('experience', true)
    );
    s += timelineSection(
      'Background',
      'Education',
      byCategory('education', true)
    );
    s += certSection();
    s += cardSection(
      'Recognition',
      'Awards &amp; rewards',
      byCategory('award', true)
    );
    s += endorsementSection();
    s += cardSection(
      'Giving back',
      'Community contributions',
      byCategory('community', true)
    );
    s += cardSection(
      'Service',
      'Volunteering',
      byCategory('volunteering', true)
    );
    s += rowSection(
      'Words',
      'Writing &amp; talks',
      byCategory('writing', true)
    );
    s += rowSection('Watch', 'Videos', byCategory('video', true));
    s += languageSection();
    s += cardSection('Beyond work', 'Interests', byCategory('interest', true));
    s += linksSection();
    s += cardSection('Also worth a mention', 'More', otherEntries());

    s += footer();
    s += '</body></html>';
    return s;
  }

  private String header() {
    String eyebrow = String.isNotBlank(roleTitle) ? roleTitle : 'Portfolio';
    String s = '<table class="hdr"><tr>';
    s += '<td class="hdr-text">';
    s += '<div class="eyebrow">' + esc(eyebrow) + '</div>';
    s += '<div class="name">' + esc(ownerName) + '</div>';
    if (String.isNotBlank(tagline)) {
      s += '<div class="tagline">' + esc(tagline) + '</div>';
    }
    String contact = contactLine();
    if (String.isNotBlank(contact)) {
      s += '<div class="contact">' + contact + '</div>';
    }
    s += '</td>';
    s +=
      '<td class="hdr-badge"><div class="initials">' +
      esc(initials) +
      '</div></td>';
    s += '</tr></table>';
    s += '<div class="rule"></div>';
    return s;
  }

  private String contactLine() {
    List<String> bits = new List<String>();
    if (String.isNotBlank(location)) {
      bits.add(esc(location));
    }
    for (Entry e : entries) {
      if (
        (e.category == 'linkedin' ||
        e.category == 'github' ||
        e.category == 'website') && String.isNotBlank(e.url)
      ) {
        bits.add(esc(prettyUrl(e.url)));
      }
    }
    return String.join(bits, '\u00A0\u00A0\u00B7\u00A0\u00A0');
  }

  // ---- Stats band -------------------------------------------------------
  private String statsBand() {
    List<StatTile> tiles = new List<StatTile>();
    Integer yrs = yearsOfExperience();
    if (yrs != null) {
      tiles.add(new StatTile(yrs + '+', 'Years experience'));
    }
    Integer certs = countCategory('certification');
    if (certs > 0) {
      tiles.add(new StatTile(String.valueOf(certs), 'Certifications'));
    }
    Integer projects = countCategory('project');
    if (projects > 0) {
      tiles.add(new StatTile(String.valueOf(projects), 'Projects'));
    }
    Integer awards = countCategory('award');
    if (awards > 0) {
      tiles.add(new StatTile(String.valueOf(awards), 'Awards'));
    }
    if (tiles.size() < 2) {
      return '';
    }
    String s = '<table class="stats"><tr>';
    for (StatTile t : tiles) {
      s +=
        '<td class="stat"><div class="stat-val">' +
        esc(t.value) +
        '</div>' +
        '<div class="stat-lbl">' +
        esc(t.label) +
        '</div></td>';
    }
    s += '</tr></table>';
    return s;
  }

  // ---- Currently --------------------------------------------------------
  private String nowCallout() {
    List<Entry> now = byCategory('now', false);
    if (now.isEmpty()) {
      return '';
    }
    Entry e = now[0];
    String s = '<div class="now"><div class="now-label">CURRENTLY</div>';
    s += '<div class="now-title">' + esc(e.title) + '</div>';
    if (String.isNotBlank(e.description)) {
      s += '<div class="now-text">' + escMultiline(e.description) + '</div>';
    }
    s += '</div>';
    return s;
  }

  // ---- About ------------------------------------------------------------
  private String aboutSection() {
    List<Entry> bios = byCategory('bio', false);
    if (bios.isEmpty()) {
      return '';
    }
    String s = sectionHead('About', ownerName);
    s += '<div class="about">';
    Boolean first = true;
    for (Entry e : bios) {
      if (String.isNotBlank(e.description)) {
        s +=
          '<div class="about-text' +
          (first ? ' about-lead' : '') +
          '">' +
          escMultiline(e.description) +
          '</div>';
        first = false;
      }
      if (String.isNotBlank(e.url)) {
        s +=
          '<div class="link-row"><a href="' +
          esc(e.url) +
          '">' +
          esc(prettyUrl(e.url)) +
          '</a></div>';
      }
    }
    s += '</div>';
    return s;
  }

  // ---- Skills -----------------------------------------------------------
  private String skillsSection() {
    Map<String, List<String>> byCat = new Map<String, List<String>>();
    List<String> order = new List<String>();
    for (Entry e : entries) {
      if (e.category != 'skill') {
        continue;
      }
      String cat = String.isNotBlank(e.subtitle)
        ? e.subtitle.trim()
        : 'General';
      if (!byCat.containsKey(cat)) {
        byCat.put(cat, new List<String>());
        order.add(cat);
      }
      byCat.get(cat).add(e.title);
      if (!e.tags.isEmpty()) {
        byCat.get(cat).addAll(e.tags);
      }
    }
    if (order.isEmpty()) {
      return '';
    }
    String s = sectionHead('Toolkit', 'Skills');
    for (String cat : order) {
      s +=
        '<div class="skill-group"><div class="skill-cat">' +
        esc(cat) +
        '</div><div class="chips">';
      for (String skill : byCat.get(cat)) {
        s += '<span class="tag tag-lg">' + esc(skill) + '</span>';
      }
      s += '</div></div>';
    }
    return s;
  }

  // ---- Featured ---------------------------------------------------------
  private String featuredSection() {
    List<Entry> items = new List<Entry>();
    for (Entry e : entries) {
      if (e.featured && e.category != 'resume') {
        items.add(e);
      }
    }
    if (items.isEmpty()) {
      return '';
    }
    String s = sectionHead('Selected work', 'Featured');
    for (Entry e : items) {
      s += '<div class="fcard">' + cardInner(e) + '</div>';
    }
    return s;
  }

  // ---- Generic card grid (2 columns) ------------------------------------
  private String cardSection(String eyebrow, String title, List<Entry> items) {
    if (items.isEmpty()) {
      return '';
    }
    String s = sectionHead(eyebrow, title);
    s += '<table class="grid"><tr>';
    Integer col = 0;
    for (Entry e : items) {
      if (col == 2) {
        s += '</tr><tr>';
        col = 0;
      }
      s += '<td class="cell"><div class="card">' + cardInner(e) + '</div></td>';
      col++;
    }
    if (col == 1) {
      s += '<td class="cell"></td>';
    }
    s += '</tr></table>';
    return s;
  }

  private String cardInner(Entry e) {
    String s = '';
    if (String.isNotBlank(e.typeLabel)) {
      s += badge(e);
    }
    s += '<div class="card-title">' + esc(e.title) + '</div>';
    if (String.isNotBlank(e.subtitle)) {
      s += '<div class="card-sub">' + esc(e.subtitle) + '</div>';
    }
    if (String.isNotBlank(e.timeframe)) {
      s += '<div class="card-date">' + esc(e.timeframe) + '</div>';
    }
    if (String.isNotBlank(e.description)) {
      s += '<div class="card-desc">' + escMultiline(e.description) + '</div>';
    }
    if (!e.tags.isEmpty()) {
      s += tagsHtml(e.tags);
    }
    if (String.isNotBlank(e.url)) {
      s +=
        '<div class="link-row"><a href="' +
        esc(e.url) +
        '">' +
        esc(e.cta) +
        ' \u2192 ' +
        esc(prettyUrl(e.url)) +
        '</a></div>';
    }
    if (String.isNotBlank(e.secondaryUrl)) {
      s +=
        '<div class="link-row link-muted"><a href="' +
        esc(e.secondaryUrl) +
        '">Source \u2192 ' +
        esc(prettyUrl(e.secondaryUrl)) +
        '</a></div>';
    }
    return s;
  }

  // ---- Timeline (experience / education) --------------------------------
  private String timelineSection(
    String eyebrow,
    String title,
    List<Entry> items
  ) {
    if (items.isEmpty()) {
      return '';
    }
    String s = sectionHead(eyebrow, title);
    s += '<table class="tl">';
    for (Entry e : items) {
      s +=
        '<tr><td class="tl-date">' +
        esc(String.isNotBlank(e.timeframe) ? e.timeframe : '') +
        '</td>';
      s +=
        '<td class="tl-body"><div class="tl-title">' +
        esc(e.title) +
        '</div>';
      if (String.isNotBlank(e.subtitle)) {
        s += '<div class="tl-sub">' + esc(e.subtitle) + '</div>';
      }
      if (String.isNotBlank(e.description)) {
        s += '<div class="tl-desc">' + escMultiline(e.description) + '</div>';
      }
      if (String.isNotBlank(e.url)) {
        s +=
          '<div class="link-row"><a href="' +
          esc(e.url) +
          '">' +
          esc(prettyUrl(e.url)) +
          '</a></div>';
      }
      s += '</td></tr>';
    }
    s += '</table>';
    return s;
  }

  // ---- Certifications (compact 2-col) -----------------------------------
  private String certSection() {
    List<Entry> items = byCategory('certification', true);
    if (items.isEmpty()) {
      return '';
    }
    String s = sectionHead('Credentials', 'Certifications');
    s += '<table class="grid"><tr>';
    Integer col = 0;
    for (Entry e : items) {
      if (col == 2) {
        s += '</tr><tr>';
        col = 0;
      }
      s += '<td class="cell"><div class="cert">';
      s += '<div class="cert-title">' + esc(e.title) + '</div>';
      if (String.isNotBlank(e.subtitle)) {
        s += '<div class="cert-sub">' + esc(e.subtitle) + '</div>';
      }
      if (String.isNotBlank(e.timeframe)) {
        s += '<div class="cert-sub">' + esc(e.timeframe) + '</div>';
      }
      if (String.isNotBlank(e.url)) {
        s +=
          '<div class="link-row"><a href="' +
          esc(e.url) +
          '">' +
          esc(prettyUrl(e.url)) +
          '</a></div>';
      }
      s += '</div></td>';
      col++;
    }
    if (col == 1) {
      s += '<td class="cell"></td>';
    }
    s += '</tr></table>';
    return s;
  }

  // ---- Endorsements -----------------------------------------------------
  private String endorsementSection() {
    List<Entry> items = byCategory('endorsement', false);
    if (items.isEmpty()) {
      return '';
    }
    String s = sectionHead('Kind words', 'Endorsements');
    for (Entry e : items) {
      s += '<div class="quote">';
      if (String.isNotBlank(e.description)) {
        s +=
          '<div class="quote-text">\u201C' +
          escMultiline(e.description) +
          '\u201D</div>';
      }
      s += '<div class="quote-author">' + esc(e.title);
      if (String.isNotBlank(e.subtitle)) {
        s += '<span class="quote-role">, ' + esc(e.subtitle) + '</span>';
      }
      s += '</div></div>';
    }
    return s;
  }

  // ---- Rows (writing / videos) ------------------------------------------
  private String rowSection(String eyebrow, String title, List<Entry> items) {
    if (items.isEmpty()) {
      return '';
    }
    String s = sectionHead(eyebrow, title);
    for (Entry e : items) {
      s +=
        '<div class="rowi"><div class="rowi-title">' +
        esc(e.title) +
        '</div>';
      if (String.isNotBlank(e.description)) {
        s += '<div class="rowi-desc">' + escMultiline(e.description) + '</div>';
      }
      if (String.isNotBlank(e.url)) {
        s +=
          '<div class="link-row"><a href="' +
          esc(e.url) +
          '">' +
          esc(e.cta) +
          ' \u2192 ' +
          esc(prettyUrl(e.url)) +
          '</a></div>';
      }
      s += '</div>';
    }
    return s;
  }

  // ---- Languages --------------------------------------------------------
  private String languageSection() {
    List<Entry> items = byCategory('language', false);
    if (items.isEmpty()) {
      return '';
    }
    String s = sectionHead('Spoken', 'Languages');
    s += '<div class="chips">';
    for (Entry e : items) {
      s +=
        '<span class="lang"><span class="lang-name">' +
        esc(e.title) +
        '</span>';
      if (String.isNotBlank(e.subtitle)) {
        s += '<span class="lang-lvl">' + esc(e.subtitle) + '</span>';
      }
      s += '</span>';
    }
    s += '</div>';
    return s;
  }

  // ---- Profiles & links -------------------------------------------------
  private String linksSection() {
    List<Entry> items = new List<Entry>();
    for (Entry e : entries) {
      if (e.featured) {
        continue;
      }
      if (
        e.category == 'linkedin' ||
        e.category == 'github' ||
        e.category == 'website' ||
        e.category == 'link'
      ) {
        items.add(e);
      }
    }
    if (items.isEmpty()) {
      return '';
    }
    String s = sectionHead('Elsewhere', 'Profiles &amp; links');
    for (Entry e : items) {
      s +=
        '<div class="link-row"><span class="link-label">' +
        esc(e.title) +
        ':</span> ';
      if (String.isNotBlank(e.url)) {
        s += '<a href="' + esc(e.url) + '">' + esc(e.url) + '</a>';
      }
      s += '</div>';
    }
    return s;
  }

  private String footer() {
    String s = '<div class="rule"></div><div class="foot">';
    s +=
      esc(ownerName) +
      '\u00A0\u00A0\u00B7\u00A0\u00A0Built on Salesforce with an Agentforce assistant';
    s += '</div>';
    return s;
  }

  // =====================================================================
  // Section helpers
  // =====================================================================
  private String sectionHead(String eyebrow, String title) {
    return '<div class="sec"><div class="sec-eyebrow">' +
      eyebrow +
      '</div><div class="sec-title">' +
      title +
      '</div></div>';
  }

  private String badge(Entry e) {
    return '<span class="badge badge-' +
      accentFor(e.category) +
      '">' +
      esc(e.typeLabel) +
      '</span>';
  }

  private String tagsHtml(List<String> tags) {
    String s = '<div class="chips">';
    for (String t : tags) {
      s += '<span class="tag">' + esc(t) + '</span>';
    }
    s += '</div>';
    return s;
  }

  private List<Entry> byCategory(String category, Boolean excludeFeatured) {
    List<Entry> out = new List<Entry>();
    for (Entry e : entries) {
      if (excludeFeatured && e.featured) {
        continue;
      }
      if (e.category == category) {
        out.add(e);
      }
    }
    return out;
  }

  /** Catch-all: active items not rendered by any dedicated section (mirrors otherItems). */
  private List<Entry> otherEntries() {
    Set<String> handled = new Set<String>{
      'bio',
      'project',
      'experience',
      'education',
      'certification',
      'award',
      'skill',
      'aitool',
      'endorsement',
      'service',
      'now',
      'language',
      'community',
      'volunteering',
      'writing',
      'video',
      'linkedin',
      'github',
      'website',
      'link',
      'interest',
      'resume',
      'skill'
    };
    List<Entry> out = new List<Entry>();
    for (Entry e : entries) {
      if (!e.featured && !handled.contains(e.category)) {
        out.add(e);
      }
    }
    return out;
  }

  private Integer countCategory(String category) {
    Integer n = 0;
    for (Entry e : entries) {
      if (e.category == category) {
        n++;
      }
    }
    return n;
  }

  private Integer yearsOfExperience() {
    Date earliest;
    for (Entry e : entries) {
      if (e.category == 'experience' && e.startDate != null) {
        if (earliest == null || e.startDate < earliest) {
          earliest = e.startDate;
        }
      }
    }
    if (earliest == null) {
      return null;
    }
    Integer years = earliest.monthsBetween(Date.today()) / 12;
    return years > 0 ? years : null;
  }

  // =====================================================================
  // Stylesheet (print-safe, CSS 2.1 only)
  // =====================================================================
  private static String css() {
    return '@page { size: a4; margin: 1.3cm 1.35cm 1.2cm; }' +
      ' body { font-family: Helvetica, Arial, sans-serif; color: ' +
      INK +
      '; font-size: 10pt; line-height: 1.45; }' +
      ' a { color: ' +
      ACCENT +
      '; text-decoration: none; }' +
      // header
      ' .hdr { width: 100%; }' +
      ' .hdr-text { vertical-align: middle; }' +
      ' .hdr-badge { width: 64px; vertical-align: middle; text-align: right; }' +
      ' .initials { width: 54px; height: 54px; background-color: ' +
      ACCENT +
      '; color: #ffffff; font-size: 20pt; font-weight: bold; text-align: center; line-height: 54px; }' +
      ' .eyebrow { color: ' +
      ACCENT +
      '; font-size: 8pt; font-weight: bold; letter-spacing: 2.5pt; text-transform: uppercase; }' +
      ' .name { color: ' +
      INK +
      '; font-size: 26pt; font-weight: bold; margin: 1pt 0 0; }' +
      ' .tagline { color: ' +
      MUTED +
      '; font-size: 10.5pt; margin: 5pt 0 0; }' +
      ' .contact { color: ' +
      INK_SOFT +
      '; font-size: 8.5pt; margin: 6pt 0 0; }' +
      ' .rule { border-bottom: 1.5pt solid ' +
      BORDER +
      '; margin: 11pt 0 2pt; }' +
      // section heads
      ' .sec { margin: 15pt 0 8pt; }' +
      ' .sec-eyebrow { color: ' +
      ACCENT +
      '; font-size: 8pt; font-weight: bold; letter-spacing: 1.5pt; text-transform: uppercase; }' +
      ' .sec-title { color: ' +
      INK +
      '; font-size: 15pt; font-weight: bold; }' +
      // stats
      ' .stats { width: 100%; margin-top: 10pt; border-collapse: separate; }' +
      ' .stat { width: 25%; border: 1pt solid ' +
      BORDER +
      '; background-color: ' +
      SURFACE +
      '; padding: 9pt 6pt; text-align: center; }' +
      ' .stat-val { color: ' +
      ACCENT +
      '; font-size: 20pt; font-weight: bold; }' +
      ' .stat-lbl { color: ' +
      MUTED +
      '; font-size: 7.5pt; font-weight: bold; letter-spacing: 0.6pt; text-transform: uppercase; margin-top: 2pt; }' +
      // now
      ' .now { background-color: ' +
      ACCENT_SOFT +
      '; border: 1pt solid #dfe3fb; border-left: 4pt solid ' +
      ACCENT +
      '; padding: 9pt 12pt; margin-top: 8pt; }' +
      ' .now-label { color: ' +
      ACCENT +
      '; font-size: 7.5pt; font-weight: bold; letter-spacing: 1.2pt; }' +
      ' .now-title { color: ' +
      INK +
      '; font-size: 12pt; font-weight: bold; margin-top: 2pt; }' +
      ' .now-text { color: ' +
      INK_SOFT +
      '; margin-top: 3pt; }' +
      // about
      ' .about-text { color: ' +
      INK_SOFT +
      '; margin-top: 6pt; }' +
      ' .about-lead { font-size: 11pt; margin-top: 0; }' +
      // cards
      ' .grid { width: 100%; border-collapse: separate; }' +
      ' .cell { width: 50%; vertical-align: top; padding: 0 5pt 10pt 0; }' +
      ' .card { border: 1pt solid ' +
      BORDER +
      '; border-left: 3pt solid ' +
      ACCENT +
      '; padding: 8pt 10pt; }' +
      ' .fcard { border: 1pt solid ' +
      BORDER +
      '; border-left: 4pt solid ' +
      ACCENT +
      '; padding: 10pt 13pt; margin: 0 0 9pt; }' +
      ' .card-title { color: ' +
      INK +
      '; font-size: 11.5pt; font-weight: bold; margin-top: 4pt; }' +
      ' .card-sub { color: ' +
      ACCENT +
      '; font-weight: bold; font-size: 9.5pt; margin-top: 1pt; }' +
      ' .card-date { color: ' +
      MUTED +
      '; font-size: 8pt; font-weight: bold; text-transform: uppercase; letter-spacing: 0.5pt; margin-top: 2pt; }' +
      ' .card-desc { color: ' +
      INK_SOFT +
      '; margin-top: 4pt; }' +
      // badges
      ' .badge { display: inline-block; font-size: 7pt; font-weight: bold; text-transform: uppercase; letter-spacing: 0.5pt; padding: 2pt 6pt; background-color: ' +
      ACCENT_SOFT +
      '; color: ' +
      ACCENT +
      '; }' +
      ' .badge-gold { background-color: #fef3c7; color: #92400e; }' +
      ' .badge-green { background-color: #dcfce7; color: #166534; }' +
      ' .badge-teal { background-color: #ccfbf1; color: #115e59; }' +
      ' .badge-slate { background-color: #e2e8f0; color: #334155; }' +
      ' .badge-blue { background-color: #dbeafe; color: #1e40af; }' +
      ' .badge-purple { background-color: #ede9fe; color: #5b21b6; }' +
      ' .badge-red { background-color: #fee2e2; color: #991b1b; }' +
      // tags / chips
      ' .chips { margin-top: 5pt; }' +
      ' .tag { display: inline-block; font-size: 8pt; color: ' +
      INK_SOFT +
      '; background-color: #f1f5f9; border: 1pt solid ' +
      BORDER +
      '; padding: 2pt 6pt; margin: 0 4pt 4pt 0; }' +
      ' .tag-lg { font-size: 9pt; padding: 3pt 8pt; }' +
      // timeline
      ' .tl { width: 100%; border-collapse: collapse; }' +
      ' .tl-date { width: 105pt; vertical-align: top; color: ' +
      MUTED +
      '; font-size: 8pt; font-weight: bold; text-transform: uppercase; letter-spacing: 0.4pt; padding: 0 8pt 12pt 0; }' +
      ' .tl-body { vertical-align: top; border-left: 2pt solid ' +
      BORDER_STRONG +
      '; padding: 0 0 12pt 12pt; }' +
      ' .tl-title { color: ' +
      INK +
      '; font-size: 11.5pt; font-weight: bold; }' +
      ' .tl-sub { color: ' +
      ACCENT +
      '; font-weight: bold; font-size: 9.5pt; margin-top: 1pt; }' +
      ' .tl-desc { color: ' +
      INK_SOFT +
      '; margin-top: 3pt; }' +
      // certifications
      ' .cert { border: 1pt solid ' +
      BORDER +
      '; padding: 8pt 10pt; }' +
      ' .cert-title { color: ' +
      INK +
      '; font-size: 10.5pt; font-weight: bold; }' +
      ' .cert-sub { color: ' +
      MUTED +
      '; font-size: 8.5pt; margin-top: 1pt; }' +
      // endorsements
      ' .quote { border: 1pt solid ' +
      BORDER +
      '; border-left: 3pt solid ' +
      ACCENT +
      '; background-color: #fafbff; padding: 9pt 12pt; margin: 0 0 8pt; }' +
      ' .quote-text { color: ' +
      INK_SOFT +
      '; font-style: italic; font-size: 10.5pt; }' +
      ' .quote-author { color: ' +
      INK +
      '; font-weight: bold; margin-top: 5pt; }' +
      ' .quote-role { color: ' +
      MUTED +
      '; font-weight: normal; }' +
      // rows
      ' .rowi { border-bottom: 1pt solid ' +
      BORDER +
      '; padding: 7pt 0; }' +
      ' .rowi-title { color: ' +
      INK +
      '; font-size: 11pt; font-weight: bold; }' +
      ' .rowi-desc { color: ' +
      MUTED +
      '; margin-top: 2pt; }' +
      // languages
      ' .lang { display: inline-block; border: 1pt solid ' +
      BORDER +
      '; padding: 4pt 9pt; margin: 0 5pt 5pt 0; }' +
      ' .lang-name { color: ' +
      INK +
      '; font-weight: bold; font-size: 9.5pt; }' +
      ' .lang-lvl { color: ' +
      MUTED +
      '; font-size: 8.5pt; }' +
      // links / misc
      ' .link-row { margin: 4pt 0 0; font-size: 9pt; }' +
      ' .link-label { color: ' +
      INK +
      '; font-weight: bold; }' +
      ' .link-muted a { color: ' +
      MUTED +
      '; }' +
      ' .foot { color: ' +
      MUTED +
      '; font-size: 8pt; text-align: center; margin-top: 4pt; }';
  }

  // =====================================================================
  // Formatting utilities
  // =====================================================================
  private static final List<String> MONTHS = new List<String>{
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  };

  private static String formatRange(Date startDate, Date endDate) {
    if (startDate == null && endDate == null) {
      return null;
    }
    String st = (startDate == null)
      ? ''
      : MONTHS[startDate.month() - 1] + ' ' + startDate.year();
    String en = (endDate == null)
      ? 'Present'
      : MONTHS[endDate.month() - 1] + ' ' + endDate.year();
    return String.isBlank(st) ? en : st + ' \u2013 ' + en;
  }

  private static List<String> splitTags(String techStack) {
    List<String> parts = new List<String>();
    if (String.isBlank(techStack)) {
      return parts;
    }
    for (String t : techStack.split(',')) {
      if (String.isNotBlank(t)) {
        parts.add(t.trim());
      }
    }
    return parts;
  }

  private static String prettyUrl(String url) {
    if (String.isBlank(url)) {
      return '';
    }
    String u = url.trim();
    u = u.replaceFirst('^https?://', '').replaceFirst('^www\\.', '');
    return u.removeEnd('/');
  }

  @TestVisible
  private static String computeInitials(String name) {
    if (String.isBlank(name)) {
      return '\u2605';
    }
    List<String> parts = name.trim().split('\\s+');
    String first = parts[0].length() > 0 ? parts[0].substring(0, 1) : '';
    String last = parts.size() > 1
      ? parts[parts.size() - 1].substring(0, 1)
      : '';
    String ini = (first + last).toUpperCase();
    return String.isBlank(ini) ? '\u2605' : ini;
  }

  private static String esc(String v) {
    return v == null ? '' : v.escapeHtml4();
  }

  private static String escMultiline(String v) {
    return v == null
      ? ''
      : v.escapeHtml4()
          .replace('\r\n', '<br/>')
          .replace('\n', '<br/>')
          .replace('\r', '<br/>');
  }

  // =====================================================================
  // Classification (mirrors classify() + CATEGORY_META in portfolioHome.js)
  // =====================================================================
  @TestVisible
  private static String classify(String type) {
    String t = (type == null) ? '' : type.toLowerCase();
    if (String.isBlank(t))
      return 'other';
    if (t.contains('youtube') || t.contains('video'))
      return 'video';
    if (t.contains('linkedin'))
      return 'linkedin';
    if (t.contains('github'))
      return 'github';
    if (t.contains('resume') || t.contains('cv'))
      return 'resume';
    if (t.contains('bio') || t.contains('about'))
      return 'bio';
    if (
      t.contains('endorsement') ||
      t.contains('testimonial') ||
      t.contains('recommendation')
    ) {
      return 'endorsement';
    }
    if (
      t == 'ai' ||
      t.contains('ai tool') ||
      t.contains('ai usage') ||
      t.contains('ai/ml') ||
      t.contains('genai')
    ) {
      return 'aitool';
    }
    if (
      t.contains('skill') ||
      t.contains('expertise') ||
      t.contains('competenc')
    )
      return 'skill';
    if (t.contains('service') || t.contains('offering'))
      return 'service';
    if (t == 'now' || t.contains('current') || t.contains('focus'))
      return 'now';
    if (t.contains('language') || t.contains('spoken'))
      return 'language';
    if (
      t.contains('award') ||
      t.contains('reward') ||
      t.contains('honor') ||
      t.contains('honour') ||
      t.contains('recognition') ||
      t.contains('prize') ||
      t.contains('accolade')
    ) {
      return 'award';
    }
    if (
      t.contains('volunteer') ||
      t.contains('nonprofit') ||
      t.contains('non-profit') ||
      t.contains('charity') ||
      t.contains('pro bono')
    ) {
      return 'volunteering';
    }
    if (
      t.contains('community') ||
      t.contains('mentor') ||
      t.contains('ambassador') ||
      t.contains('user group') ||
      t.contains('meetup') ||
      t.contains('advocate') ||
      t.contains('mvp')
    ) {
      return 'community';
    }
    if (
      t.contains('interest') ||
      t.contains('hobby') ||
      t.contains('hobbies') ||
      t.contains('passion')
    ) {
      return 'interest';
    }
    if (t.contains('project'))
      return 'project';
    if (
      t.contains('experience') ||
      t.contains('work') ||
      t.contains('role') ||
      t.contains('job')
    ) {
      return 'experience';
    }
    if (
      t.contains('education') ||
      t.contains('degree') ||
      t.contains('school') ||
      t.contains('university')
    ) {
      return 'education';
    }
    if (t.contains('cert'))
      return 'certification';
    if (t.contains('website') || t.contains('portfolio') || t.contains('site'))
      return 'website';
    if (
      t.contains('blog') ||
      t.contains('publication') ||
      t.contains('article') ||
      t.contains('paper') ||
      t.contains('writing') ||
      t.contains('talk') ||
      t.contains('podcast')
    ) {
      return 'writing';
    }
    if (t.contains('link') || t.contains('profile'))
      return 'link';
    return 'other';
  }

  /** Maps a category to its badge accent (mirrors CATEGORY_META accents). */
  private static String accentFor(String category) {
    switch on category {
      when 'experience', 'education', 'endorsement', 'language', 'community' {
        return 'teal';
      }
      when 'writing', 'service', 'volunteering' {
        return 'green';
      }
      when 'video' {
        return 'red';
      }
      when 'certification', 'award' {
        return 'gold';
      }
      when 'resume', 'interest' {
        return 'purple';
      }
      when 'linkedin' {
        return 'blue';
      }
      when 'github', 'other' {
        return 'slate';
      }
      when else {
        return 'indigo';
      }
    }
  }

  private static String ctaFor(String category) {
    switch on category {
      when 'project' {
        return 'View project';
      }
      when 'video' {
        return 'Watch on YouTube';
      }
      when 'writing' {
        return 'Read article';
      }
      when 'certification' {
        return 'View credential';
      }
      when 'linkedin', 'github' {
        return 'View profile';
      }
      when else {
        return 'Learn more';
      }
    }
  }

  // =====================================================================
  // Wrappers
  // =====================================================================
  private class Entry {
    String title;
    String subtitle;
    String description;
    String typeLabel;
    String category;
    String url;
    String secondaryUrl;
    String timeframe;
    String cta;
    Date startDate;
    Date endDate;
    Boolean featured;
    List<String> tags;

    Entry(Portfolio_Item__c p) {
      this.title = p.Name;
      this.subtitle = String.isBlank(p.Subtitle__c) ? null : p.Subtitle__c;
      this.description = String.isBlank(p.Description__c)
        ? null
        : p.Description__c;
      this.typeLabel = String.isBlank(p.Type__c) ? null : p.Type__c;
      this.category = classify(p.Type__c);
      this.url = String.isBlank(p.URL__c) ? null : p.URL__c;
      this.secondaryUrl = String.isBlank(p.Secondary_URL__c)
        ? null
        : p.Secondary_URL__c;
      this.startDate = p.Start_Date__c;
      this.endDate = p.End_Date__c;
      this.timeframe = formatRange(p.Start_Date__c, p.End_Date__c);
      this.featured = p.Is_Featured__c == true;
      this.tags = splitTags(p.Tech_Stack__c);
      this.cta = ctaFor(this.category);
    }
  }

  private class StatTile {
    String value;
    String label;
    StatTile(String value, String label) {
      this.value = value;
      this.label = label;
    }
  }
}
