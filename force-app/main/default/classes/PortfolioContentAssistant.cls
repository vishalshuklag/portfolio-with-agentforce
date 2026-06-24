/**
 * Backs the portfolioItemAssistant LWC (Portfolio Manager console).
 * Lists all Portfolio Items and lets the owner create, update, and delete them,
 * with AI drafting for the Description and Resume Details fields via the
 * Salesforce Models API (aiplatform.ModelsAPI). No prompt templates or external
 * setup required — the model is called directly from Apex.
 */
public with sharing class PortfolioContentAssistant {

    // Default Salesforce-managed model. Change here if your org standardizes on another.
    private static final String MODEL_NAME = 'sfdc_ai__DefaultOpenAIGPT4OmniMini';

    private static final String FIELD_DESCRIPTION = 'Description__c';
    private static final String FIELD_RESUME = 'Resume_Details__c';

    public class ItemDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String type;
        @AuraEnabled public String url;
        @AuraEnabled public String secondaryUrl;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String description;
        @AuraEnabled public String resumeDetails;
        @AuraEnabled public String techStack;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Boolean featured;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Decimal sortOrder;
    }

    @AuraEnabled(cacheable=true)
    public static List<ItemDTO> listItems() {
        List<ItemDTO> result = new List<ItemDTO>();
        for (Portfolio_Item__c record : [
            SELECT Id, Name, Subtitle__c, Type__c, URL__c, Secondary_URL__c,
                   Image_URL__c, Description__c, Resume_Details__c, Tech_Stack__c,
                   Start_Date__c, End_Date__c, Is_Featured__c, Active__c, Sort_Order__c
            FROM Portfolio_Item__c
            WITH USER_MODE
            ORDER BY Is_Featured__c DESC, Sort_Order__c ASC NULLS LAST, Name ASC
            LIMIT 500
        ]) {
            result.add(toDTO(record));
        }
        return result;
    }

    @AuraEnabled
    public static ItemDTO saveItem(String itemJson) {
        ItemDTO item;
        try {
            item = (ItemDTO) JSON.deserialize(itemJson, ItemDTO.class);
        } catch (Exception e) {
            throw new AuraHandledException('Could not read the item details. Please try again.');
        }
        if (item == null || String.isBlank(item.name)) {
            throw new AuraHandledException('A title (Name) is required.');
        }
        if (String.isBlank(item.type)) {
            throw new AuraHandledException('A type is required.');
        }

        Portfolio_Item__c record = new Portfolio_Item__c();
        if (String.isNotBlank(item.id)) {
            record.Id = item.id;
        }
        record.Name = item.name;
        record.Subtitle__c = item.subtitle;
        record.Type__c = item.type;
        record.URL__c = item.url;
        record.Secondary_URL__c = item.secondaryUrl;
        record.Image_URL__c = item.imageUrl;
        record.Description__c = item.description;
        record.Resume_Details__c = item.resumeDetails;
        record.Tech_Stack__c = item.techStack;
        record.Start_Date__c = item.startDate;
        record.End_Date__c = item.endDate;
        record.Is_Featured__c = item.featured == null ? false : item.featured;
        record.Active__c = item.active == null ? true : item.active;
        record.Sort_Order__c = item.sortOrder;

        try {
            upsert as user record;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }

        return getItem(record.Id);
    }

    @AuraEnabled
    public static void deleteItem(Id recordId) {
        try {
            Portfolio_Item__c record = [
                SELECT Id FROM Portfolio_Item__c
                WHERE Id = :recordId WITH USER_MODE LIMIT 1
            ];
            delete as user record;
        } catch (Exception e) {
            throw new AuraHandledException('Could not delete item: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static ItemDTO getItem(Id recordId) {
        Portfolio_Item__c record = [
            SELECT Id, Name, Subtitle__c, Type__c, URL__c, Secondary_URL__c,
                   Image_URL__c, Description__c, Resume_Details__c, Tech_Stack__c,
                   Start_Date__c, End_Date__c, Is_Featured__c, Active__c, Sort_Order__c
            FROM Portfolio_Item__c
            WHERE Id = :recordId WITH USER_MODE LIMIT 1
        ];
        return toDTO(record);
    }

    /**
     * Context-free generation used by the manager console. Works for both new
     * (unsaved) items and existing ones — the LWC passes whatever it has on screen.
     */
    @AuraEnabled
    public static String generateText(
        String title,
        String type,
        String url,
        String targetField,
        String existing,
        String instruction,
        String modelName
    ) {
        String prompt = buildPrompt(title, type, url, targetField, existing, instruction);
        return callModel(prompt, modelName);
    }

    /**
     * Returns the exact prompt that generateText() would send to the model for the
     * same inputs, without calling the LLM or consuming Einstein Requests. Lets the
     * UI show the final prompt so a user can verify it before clicking Generate.
     */
    @AuraEnabled
    public static String previewPrompt(
        String title,
        String type,
        String url,
        String targetField,
        String existing,
        String instruction
    ) {
        return buildPrompt(title, type, url, targetField, existing, instruction);
    }

    /**
     * Sends a final prompt to the model exactly as provided. Used when the user
     * previews and optionally edits the prompt in the UI before generating, so the
     * text they see is precisely what the model receives.
     */
    @AuraEnabled
    public static String generateFromPrompt(String prompt, String modelName) {
        if (String.isBlank(prompt)) {
            throw new AuraHandledException(
                'The prompt is empty. Add text or rebuild it from the fields.'
            );
        }
        return callModel(prompt, modelName);
    }

    // ---- Backward-compatible record-page methods --------------------------

    public class Context {
        @AuraEnabled public String title;
        @AuraEnabled public String type;
        @AuraEnabled public String url;
        @AuraEnabled public String description;
        @AuraEnabled public String resumeDetails;
    }

    @AuraEnabled(cacheable=true)
    public static Context getContext(Id recordId) {
        Portfolio_Item__c record = [
            SELECT Name, Type__c, URL__c, Description__c, Resume_Details__c
            FROM Portfolio_Item__c
            WHERE Id = :recordId
            WITH USER_MODE
            LIMIT 1
        ];
        Context ctx = new Context();
        ctx.title = record.Name;
        ctx.type = record.Type__c;
        ctx.url = record.URL__c;
        ctx.description = record.Description__c;
        ctx.resumeDetails = record.Resume_Details__c;
        return ctx;
    }

    @AuraEnabled
    public static String generate(Id recordId, String targetField, String instruction) {
        Context ctx = getContext(recordId);
        String existing = normalizeField(targetField) == FIELD_RESUME
            ? ctx.resumeDetails
            : ctx.description;
        return generateText(ctx.title, ctx.type, ctx.url, targetField, existing, instruction, null);
    }

    @AuraEnabled
    public static void save(Id recordId, String targetField, String value) {
        String field = normalizeField(targetField);
        Portfolio_Item__c record = new Portfolio_Item__c(Id = recordId);
        if (field == FIELD_RESUME) {
            record.Resume_Details__c = value == null ? null : value.replace('\n', '<br/>');
        } else {
            record.Description__c = value;
        }
        update as user record;
    }

    // ---- Helpers ----------------------------------------------------------

    private static ItemDTO toDTO(Portfolio_Item__c record) {
        ItemDTO dto = new ItemDTO();
        dto.id = record.Id;
        dto.name = record.Name;
        dto.subtitle = record.Subtitle__c;
        dto.type = record.Type__c;
        dto.url = record.URL__c;
        dto.secondaryUrl = record.Secondary_URL__c;
        dto.imageUrl = record.Image_URL__c;
        dto.description = record.Description__c;
        dto.resumeDetails = record.Resume_Details__c;
        dto.techStack = record.Tech_Stack__c;
        dto.startDate = record.Start_Date__c;
        dto.endDate = record.End_Date__c;
        dto.featured = record.Is_Featured__c;
        dto.active = record.Active__c;
        dto.sortOrder = record.Sort_Order__c;
        return dto;
    }

    private static String callModel(String prompt, String modelName) {
        String model = String.isBlank(modelName) ? MODEL_NAME : modelName;
        try {
            aiplatform.ModelsAPI.createGenerations_Request request =
                new aiplatform.ModelsAPI.createGenerations_Request();
            request.modelName = model;

            aiplatform.ModelsAPI_GenerationRequest body =
                new aiplatform.ModelsAPI_GenerationRequest();
            body.prompt = prompt;
            request.body = body;

            aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI();
            aiplatform.ModelsAPI.createGenerations_Response response =
                modelsAPI.createGenerations(request);

            if (response != null
                && response.Code200 != null
                && response.Code200.generation != null) {
                return response.Code200.generation.generatedText;
            }
            throw new AuraHandledException('The model returned no content. Please try again.');
        } catch (aiplatform.ModelsAPI.createGenerations_ResponseException e) {
            throw new AuraHandledException(
                'Models API error (' + e.responseCode + '): ' + e.getMessage()
            );
        } catch (Exception e) {
            throw new AuraHandledException('Could not generate content: ' + e.getMessage());
        }
    }

    private static String normalizeField(String targetField) {
        return FIELD_RESUME.equalsIgnoreCase(targetField) ? FIELD_RESUME : FIELD_DESCRIPTION;
    }

    private static String buildPrompt(
        String title,
        String type,
        String url,
        String targetField,
        String existing,
        String instruction
    ) {
        String field = normalizeField(targetField);

        String fieldGoal = field == FIELD_RESUME
            ? 'clear, well-structured, in-depth details for this item. If it is a resume, cover relevant experience, skills, education, and achievements; otherwise provide the key facts, highlights, and supporting context a visitor would want to know'
            : 'a concise, engaging description (2-4 sentences) suitable for a public portfolio website';

        String task = String.isNotBlank(instruction)
            ? instruction
            : (String.isNotBlank(existing)
                ? 'Improve and polish the existing content below.'
                : 'Write new content from scratch using the item details.');

        return 'You are helping a professional write content for their public portfolio.\n'
            + 'Write ' + fieldGoal + '.\n'
            + 'Return ONLY the final text with no preamble, headings, or quotation marks.\n\n'
            + 'Portfolio item title: ' + valueOrUnknown(title) + '\n'
            + 'Category/type: ' + valueOrUnknown(type) + '\n'
            + 'Link: ' + valueOrUnknown(url) + '\n\n'
            + 'Existing content (may be empty):\n' + valueOrUnknown(existing) + '\n\n'
            + 'Instruction: ' + task;
    }

    private static String valueOrUnknown(String value) {
        return String.isBlank(value) ? '(none provided)' : value;
    }
}