/**
 * First-run setup helper. Takes a pasted resume, asks the Salesforce Models API
 * (aiplatform.ModelsAPI) to extract structured portfolio items as JSON, and
 * creates Portfolio_Item__c records from them. Powers the portfolioOnboarding LWC.
 */
public with sharing class PortfolioOnboardingService {
  private static final String DEFAULT_MODEL = 'sfdc_ai__DefaultOpenAIGPT4OmniMini';
  private static final Set<String> ALLOWED_TYPES = new Set<String>{
    'Bio',
    'Experience',
    'Skill',
    'Education',
    'Project',
    'Certification',
    'LinkedIn',
    'GitHub',
    'Website',
    'Blog',
    'Publication'
  };

  public class GeneratedItem {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String itemType;
    @AuraEnabled
    public String subtitle;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String url;
    @AuraEnabled
    public String techStack;
    @AuraEnabled
    public String startDate;
    @AuraEnabled
    public String endDate;
    @AuraEnabled
    public Boolean featured;
  }

  /**
   * Step 1 — parse the resume into a preview list of items (no DML).
   */
  @AuraEnabled
  public static List<GeneratedItem> generateFromResume(
    String resumeText,
    String modelName
  ) {
    if (String.isBlank(resumeText)) {
      throw new AuraHandledException('Please paste your resume text first.');
    }
    String raw = callModel(buildPrompt(resumeText), modelName);

    System.debug(
      'PortfolioOnboardingService.generateFromResume: raw=' +
      JSON.serialize(raw)
    );

    return parseItems(raw);
  }

  /**
   * Step 2 — persist the (reviewed) items as Portfolio_Item__c records.
   *
   * Idempotent: each item is matched to the current user's existing records by
   * a natural key (see makeKey). Matches are updated in place; only brand-new
   * items are inserted. This means re-running onboarding with an updated resume
   * refreshes the portfolio instead of creating duplicates. Manually curated
   * fields that the resume never sets (image, secondary URL, sort order, active
   * flag, featured flag) are preserved on update.
   */
  @AuraEnabled
  public static Integer createRecords(
    String itemsJson,
    String resumeText,
    Boolean includeResumeRecord
  ) {
    List<GeneratedItem> items = parseGeneratedItems(itemsJson);

    Map<String, Portfolio_Item__c> existingByKey = loadExistingByKey();
    Map<String, Portfolio_Item__c> resultByKey = new Map<String, Portfolio_Item__c>();
    Integer nextOrder = nextSortOrder(existingByKey.values());

    for (GeneratedItem gi : items) {
      if (gi == null || String.isBlank(gi.name)) {
        continue;
      }
      String type = normalizeType(gi.itemType);
      String key = makeKey(type, gi.name);
      if (resultByKey.containsKey(key)) {
        continue; // first occurrence wins within a single run
      }
      Portfolio_Item__c rec = existingByKey.get(key);
      if (rec == null) {
        rec = new Portfolio_Item__c();
        rec.Active__c = true;
        rec.Sort_Order__c = nextOrder++;
        rec.Is_Featured__c = (gi.featured == true);
      } else if (gi.featured == true) {
        rec.Is_Featured__c = true; // promote, but never unset a manual choice
      }
      rec.Name = trimTo(gi.name, 80);
      rec.Type__c = type;
      applyContent(rec, gi);
      resultByKey.put(key, rec);
    }

    if (includeResumeRecord == true && String.isNotBlank(resumeText)) {
      String key = makeKey('Resume', 'Resume');
      Portfolio_Item__c rec = resultByKey.containsKey(key)
        ? resultByKey.get(key)
        : existingByKey.get(key);
      if (rec == null) {
        rec = new Portfolio_Item__c();
        rec.Active__c = true;
        rec.Sort_Order__c = nextOrder++;
      }
      rec.Name = 'Resume';
      rec.Type__c = 'Resume';
      if (String.isBlank(rec.Subtitle__c)) {
        rec.Subtitle__c = 'Full resume';
      }
      rec.Resume_Details__c = toHtml(trimTo(resumeText, 120000));
      resultByKey.put(key, rec);
    }

    List<Portfolio_Item__c> toUpsert = resultByKey.values();
    if (toUpsert.isEmpty()) {
      throw new AuraHandledException(
        'No valid items to save from ' +
          items.size() +
          ' generated item(s). Each item needs at least a name. Please generate again.'
      );
    }

    try {
      upsert as user toUpsert;
    } catch (DmlException e) {
      throw new AuraHandledException(e.getDmlMessage(0));
    }
    return toUpsert.size();
  }

  /**
   * Copies resume-derived values onto a record, but only when the generated
   * value is non-blank, so an update never blanks out existing content.
   */
  private static void applyContent(Portfolio_Item__c rec, GeneratedItem gi) {
    String subtitle = trimTo(gi.subtitle, 255);
    if (String.isNotBlank(subtitle)) {
      rec.Subtitle__c = subtitle;
    }
    String description = trimTo(gi.description, 32000);
    if (String.isNotBlank(description)) {
      rec.Description__c = description;
    }
    String url = trimTo(gi.url, 255);
    if (String.isNotBlank(url)) {
      rec.URL__c = url;
    }
    String tech = trimTo(gi.techStack, 255);
    if (String.isNotBlank(tech)) {
      rec.Tech_Stack__c = tech;
    }
    Date startDate = parseDate(gi.startDate);
    if (startDate != null) {
      rec.Start_Date__c = startDate;
    }
    Date endDate = parseDate(gi.endDate);
    if (endDate != null) {
      rec.End_Date__c = endDate;
    }
  }

  /**
   * Loads the current user's existing items keyed by natural key. Only the
   * fields needed for matching/ordering are queried, so fields left off the
   * query (image, description, etc.) are untouched by the later upsert.
   */
  private static Map<String, Portfolio_Item__c> loadExistingByKey() {
    Map<String, Portfolio_Item__c> byKey = new Map<String, Portfolio_Item__c>();
    for (Portfolio_Item__c p : [
      SELECT Id, Name, Type__c, Subtitle__c, Sort_Order__c
      FROM Portfolio_Item__c
      WHERE OwnerId = :UserInfo.getUserId()
      WITH USER_MODE
    ]) {
      String key = makeKey(p.Type__c, p.Name);
      if (!byKey.containsKey(key)) {
        byKey.put(key, p); // first match wins; pre-existing dupes left as-is
      }
    }
    return byKey;
  }

  private static Integer nextSortOrder(List<Portfolio_Item__c> existing) {
    Integer maxOrder = -1;
    for (Portfolio_Item__c p : existing) {
      if (p.Sort_Order__c != null && p.Sort_Order__c.intValue() > maxOrder) {
        maxOrder = p.Sort_Order__c.intValue();
      }
    }
    return maxOrder + 1;
  }

  // Types that exist at most once per portfolio — matched by type alone so a
  // re-run updates the single record even if the AI words the name differently.
  private static final Set<String> SINGLETON_TYPES = new Set<String>{
    'Bio',
    'Resume',
    'LinkedIn',
    'GitHub',
    'Website',
    'Blog',
    'YouTube'
  };

  /**
   * Natural key used to match a generated item to an existing record:
   * singleton types match by type; everything else by type + normalized name.
   */
  private static String makeKey(String type, String name) {
    String t = String.isBlank(type) ? 'Project' : type.trim();
    if (SINGLETON_TYPES.contains(t)) {
      return t.toLowerCase();
    }
    String n = (name == null) ? '' : name.toLowerCase().normalizeSpace();
    return t.toLowerCase() + '|' + n;
  }

  // ---- Helpers ----------------------------------------------------------

  private static String buildPrompt(String resumeText) {
    return 'You convert a professional\'s resume into structured portfolio items for their website.\n' +
      'Return ONLY valid minified JSON, with no markdown fences or commentary, exactly in this shape:\n' +
      '{"items":[{"name":"","itemType":"","subtitle":"","description":"","url":"","techStack":"","startDate":"","endDate":"","featured":false}]}\n' +
      'Allowed itemType values: Bio, Experience, Education, Project, Certification, LinkedIn, GitHub, Website, Blog, Publication, Skill.\n' +
      'Guidance:\n' +
      '- Exactly one Bio item: name = the person\'s full name, description = a 2-3 sentence professional summary, dates empty.\n' +
      '- Skill -> itemType Skill, Subtitle = specific sections: "Technical Core", "Declarative vs. Programmatic", and "AI & Agentforce Capabilities"\n' +
      '- Each role -> itemType Experience: name = job title, subtitle = company, description = 1-2 sentences on scope/impact, startDate and endDate as yyyy-MM-dd (use day 01; leave endDate empty for the current role).\n' +
      '- Each degree -> itemType Education: name = degree, subtitle = institution, dates as above.\n' +
      '- Notable projects -> itemType Project with techStack as a comma-separated list; set featured=true for at most 2 of the strongest.\n' +
      '- Certifications -> itemType Certification, subtitle = issuing body.\n' +
      '- If LinkedIn, GitHub, a personal website, or a blog URL appears, add items of those types with the url set.\n' +
      '- Use ONLY facts present in the resume. Never invent employers, titles, dates, or links. Use "" for anything not present.\n' +
      'Resume:\n"""\n' +
      resumeText +
      '\n"""';
  }

  @TestVisible
  private static List<GeneratedItem> parseItems(String raw) {
    String clean = extractJson(raw);
    if (String.isBlank(clean)) {
      throw new AuraHandledException(
        'Could not read the AI response. Please try again.'
      );
    }
    try {
      return toGeneratedItems(JSON.deserializeUntyped(clean));
    } catch (Exception e) {
      throw new AuraHandledException(
        'The AI response was not valid JSON. Please try again.'
      );
    }
  }

  /**
   * Parses the items handed back from the LWC. The component sends a JSON
   * string (not a typed list) so the values survive the round trip: binding
   * Apex-returned objects straight back into a custom-type parameter can
   * deserialize them as empty instances.
   */
  private static List<GeneratedItem> parseGeneratedItems(String payload) {
    if (String.isBlank(payload)) {
      return new List<GeneratedItem>();
    }
    try {
      return toGeneratedItems(JSON.deserializeUntyped(payload));
    } catch (Exception e) {
      return new List<GeneratedItem>();
    }
  }

  /**
   * Accepts either a JSON array of items or an object with an "items" array,
   * then maps each entry tolerantly to a GeneratedItem.
   */
  private static List<GeneratedItem> toGeneratedItems(Object parsed) {
    List<Object> rawItems = null;
    if (parsed instanceof List<Object>) {
      rawItems = (List<Object>) parsed;
    } else if (parsed instanceof Map<String, Object>) {
      Object itemsObj = ((Map<String, Object>) parsed).get('items');
      if (itemsObj instanceof List<Object>) {
        rawItems = (List<Object>) itemsObj;
      }
    }
    List<GeneratedItem> result = new List<GeneratedItem>();
    if (rawItems == null) {
      return result;
    }
    for (Object o : rawItems) {
      if (o instanceof Map<String, Object>) {
        result.add(toGeneratedItem((Map<String, Object>) o));
      }
    }
    return result;
  }

  /**
   * Maps one raw JSON object to a GeneratedItem, tolerating common key
   * variations across models (e.g. "type" instead of "itemType") so a
   * non-conforming response does not silently produce empty items.
   */
  private static GeneratedItem toGeneratedItem(Map<String, Object> m) {
    GeneratedItem gi = new GeneratedItem();
    gi.name = asString(firstOf(m, new List<String>{ 'name', 'title' }));
    gi.itemType = asString(
      firstOf(m, new List<String>{ 'itemType', 'type', 'category' })
    );
    gi.subtitle = asString(
      firstOf(
        m,
        new List<String>{ 'subtitle', 'company', 'institution', 'issuer' }
      )
    );
    gi.description = asString(
      firstOf(m, new List<String>{ 'description', 'summary' })
    );
    gi.url = asString(firstOf(m, new List<String>{ 'url', 'link' }));
    gi.techStack = asString(
      firstOf(
        m,
        new List<String>{ 'techStack', 'tech', 'technologies', 'skills' }
      )
    );
    gi.startDate = asString(
      firstOf(m, new List<String>{ 'startDate', 'start' })
    );
    gi.endDate = asString(firstOf(m, new List<String>{ 'endDate', 'end' }));
    Object f = firstOf(
      m,
      new List<String>{ 'featured', 'isFeatured', 'is_featured' }
    );
    gi.featured = (f instanceof Boolean)
      ? (Boolean) f
      : (f != null && String.valueOf(f).equalsIgnoreCase('true'));
    return gi;
  }

  private static Object firstOf(Map<String, Object> m, List<String> keys) {
    for (String k : keys) {
      if (m.containsKey(k) && m.get(k) != null) {
        return m.get(k);
      }
    }
    for (String k : keys) {
      for (String actual : m.keySet()) {
        if (actual.equalsIgnoreCase(k) && m.get(actual) != null) {
          return m.get(actual);
        }
      }
    }
    return null;
  }

  private static String asString(Object o) {
    if (o == null) {
      return null;
    }
    if (o instanceof List<Object>) {
      List<String> parts = new List<String>();
      for (Object e : (List<Object>) o) {
        if (e != null) {
          parts.add(String.valueOf(e));
        }
      }
      return String.join(parts, ', ');
    }
    return String.valueOf(o);
  }

  private static String extractJson(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String s = raw.trim();
    if (s.contains('```')) {
      s = s.replaceAll('```json', '```');
      Integer first = s.indexOf('```');
      Integer second = s.indexOf('```', first + 3);
      if (second > first) {
        s = s.substring(first + 3, second);
      }
    }
    Integer start = s.indexOf('{');
    Integer endIdx = s.lastIndexOf('}');
    if (start >= 0 && endIdx > start) {
      return s.substring(start, endIdx + 1);
    }
    return null;
  }

  private static String normalizeType(String t) {
    if (String.isBlank(t)) {
      return 'Project';
    }
    String trimmed = t.trim();
    for (String allowed : ALLOWED_TYPES) {
      if (allowed.equalsIgnoreCase(trimmed)) {
        return allowed;
      }
    }
    String lower = trimmed.toLowerCase();
    if (
      lower.contains('work') ||
      lower.contains('employ') ||
      lower.contains('job') ||
      lower.contains('role')
    ) {
      return 'Experience';
    }
    if (
      lower.contains('school') ||
      lower.contains('degree') ||
      lower.contains('univers')
    ) {
      return 'Education';
    }
    if (lower.contains('cert')) {
      return 'Certification';
    }
    if (
      lower.contains('skill') ||
      lower.contains('abilit') ||
      lower.contains('competenc') ||
      lower.contains('expertise') ||
      lower.contains('proficienc')
    ) {
      return 'Skill';
    }
    return trimmed;
  }

  private static Date parseDate(String s) {
    if (String.isBlank(s)) {
      return null;
    }
    String v = s.trim();
    if (
      v.equalsIgnoreCase('present') ||
      v.equalsIgnoreCase('current') ||
      v.equalsIgnoreCase('now')
    ) {
      return null;
    }
    if (Pattern.matches('^\\d{4}$', v)) {
      v = v + '-01-01';
    } else if (Pattern.matches('^\\d{4}-\\d{1,2}$', v)) {
      v = v + '-01';
    }
    try {
      List<String> parts = v.split('-');
      return Date.newInstance(
        Integer.valueOf(parts[0]),
        Integer.valueOf(parts[1]),
        Integer.valueOf(parts[2])
      );
    } catch (Exception e) {
      return null;
    }
  }

  private static String toHtml(String text) {
    if (String.isBlank(text)) {
      return null;
    }
    return text.escapeHtml4()
      .replace('\r\n', '<br/>')
      .replace('\n', '<br/>')
      .replace('\r', '<br/>');
  }

  private static String trimTo(String v, Integer max) {
    if (v == null) {
      return null;
    }
    String t = v.trim();
    return t.length() > max ? t.substring(0, max) : t;
  }

  private static String callModel(String prompt, String modelName) {
    String model = String.isBlank(modelName) ? DEFAULT_MODEL : modelName;
    try {
      aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
      request.modelName = model;

      aiplatform.ModelsAPI_GenerationRequest body = new aiplatform.ModelsAPI_GenerationRequest();
      body.prompt = prompt;
      request.body = body;

      aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI();
      aiplatform.ModelsAPI.createGenerations_Response response = modelsAPI.createGenerations(
        request
      );

      if (
        response != null &&
        response.Code200 != null &&
        response.Code200.generation != null
      ) {
        return response.Code200.generation.generatedText;
      }
      throw new AuraHandledException(
        'The model returned no content. Please try again.'
      );
    } catch (aiplatform.ModelsAPI.createGenerations_ResponseException e) {
      throw new AuraHandledException(
        'Models API error (' + e.responseCode + '): ' + e.getMessage()
      );
    } catch (Exception e) {
      throw new AuraHandledException(
        'Could not generate content: ' + e.getMessage()
      );
    }
  }
}
