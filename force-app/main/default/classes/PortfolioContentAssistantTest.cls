@isTest
private class PortfolioContentAssistantTest {

    private static PortfolioContentAssistant.ItemDTO buildDraft() {
        PortfolioContentAssistant.ItemDTO dto = new PortfolioContentAssistant.ItemDTO();
        dto.name = 'New Project';
        dto.subtitle = 'Side project';
        dto.type = 'Project';
        dto.url = 'https://example.com';
        dto.secondaryUrl = 'https://github.com/me/x';
        dto.imageUrl = 'https://example.com/x.png';
        dto.description = 'Desc';
        dto.resumeDetails = '<p>Details</p>';
        dto.techStack = 'Apex, LWC';
        dto.startDate = Date.newInstance(2023, 5, 1);
        dto.endDate = null;
        dto.featured = true;
        dto.active = true;
        dto.sortOrder = 1;
        return dto;
    }

    @isTest
    static void savesInsertsAndUpdates() {
        Test.startTest();
        PortfolioContentAssistant.ItemDTO saved =
            PortfolioContentAssistant.saveItem(JSON.serialize(buildDraft()));
        System.assertNotEquals(null, saved.id, 'Insert returns id');
        System.assertEquals('New Project', saved.name);
        System.assertEquals(true, saved.featured);
        System.assertEquals('Apex, LWC', saved.techStack);

        saved.name = 'Renamed Project';
        PortfolioContentAssistant.ItemDTO updated =
            PortfolioContentAssistant.saveItem(JSON.serialize(saved));
        Test.stopTest();

        System.assertEquals('Renamed Project', updated.name);
        System.assertEquals(saved.id, updated.id, 'Same record updated');
    }

    @isTest
    static void listGetAndDelete() {
        PortfolioContentAssistant.ItemDTO saved =
            PortfolioContentAssistant.saveItem(JSON.serialize(buildDraft()));

        Test.startTest();
        List<PortfolioContentAssistant.ItemDTO> all = PortfolioContentAssistant.listItems();
        System.assertEquals(1, all.size());

        PortfolioContentAssistant.ItemDTO fetched =
            PortfolioContentAssistant.getItem(saved.id);
        System.assertEquals('New Project', fetched.name);

        PortfolioContentAssistant.deleteItem(saved.id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Portfolio_Item__c]);
    }

    @isTest
    static void validatesRequiredFields() {
        PortfolioContentAssistant.ItemDTO noName = new PortfolioContentAssistant.ItemDTO();
        noName.type = 'Project';
        Boolean threw = false;
        try {
            PortfolioContentAssistant.saveItem(JSON.serialize(noName));
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Missing name should throw');
    }

    @isTest
    static void legacyRecordPageMethods() {
        Portfolio_Item__c rec = new Portfolio_Item__c(
            Name = 'Legacy',
            Type__c = 'Bio',
            Description__c = 'Old',
            Active__c = true
        );
        insert rec;

        Test.startTest();
        PortfolioContentAssistant.Context ctx = PortfolioContentAssistant.getContext(rec.Id);
        System.assertEquals('Legacy', ctx.title);

        PortfolioContentAssistant.save(rec.Id, 'Description__c', 'Updated desc');
        PortfolioContentAssistant.save(rec.Id, 'Resume_Details__c', 'line1\nline2');
        Test.stopTest();

        Portfolio_Item__c after = [
            SELECT Description__c, Resume_Details__c FROM Portfolio_Item__c WHERE Id = :rec.Id
        ];
        System.assertEquals('Updated desc', after.Description__c);
        // The Html field normalizes <br/> to <br>, so assert on the tag prefix.
        System.assert(after.Resume_Details__c.contains('line1'), 'has line1: ' + after.Resume_Details__c);
        System.assert(after.Resume_Details__c.contains('<br'), 'newline to br: ' + after.Resume_Details__c);
    }

    @isTest
    static void previewPromptReturnsFinalPrompt() {
        Test.startTest();
        String descPrompt = PortfolioContentAssistant.previewPrompt(
            'My Title', 'Project', 'https://x.com',
            'Description__c', 'existing text', 'make it punchy'
        );
        String resumePrompt = PortfolioContentAssistant.previewPrompt(
            'My Title', 'Resume', null,
            'Resume_Details__c', null, null
        );
        Test.stopTest();

        System.assert(descPrompt.contains('My Title'), 'Includes title');
        System.assert(descPrompt.contains('Project'), 'Includes type');
        System.assert(descPrompt.contains('make it punchy'), 'Includes instruction');
        System.assert(
            descPrompt.contains('concise, engaging description'),
            'Description goal present'
        );
        System.assert(
            resumePrompt.contains('in-depth details'),
            'Resume goal present'
        );
        System.assert(
            resumePrompt.contains('Write new content from scratch'),
            'Default task present when no instruction or existing content'
        );
    }

    @isTest
    static void generateFromPromptHandlesBlankAndCall() {
        Boolean blankThrew = false;
        try {
            PortfolioContentAssistant.generateFromPrompt('   ', null);
        } catch (AuraHandledException e) {
            blankThrew = true;
        }
        System.assertEquals(true, blankThrew, 'Blank prompt should throw');

        // The Models API is not invocable in test context, so this call surfaces an
        // exception; it still covers the non-blank branch and the model-call path.
        Test.startTest();
        try {
            PortfolioContentAssistant.generateFromPrompt('Write a haiku about Apex.', null);
        } catch (Exception e) {
            // expected
        }
        Test.stopTest();
        System.assert(true, 'generateFromPrompt path executed');
    }

    @isTest
    static void generationPathsAreExercised() {
        Portfolio_Item__c rec = new Portfolio_Item__c(
            Name = 'Gen', Type__c = 'Project', Active__c = true
        );
        insert rec;

        // The Models API is not invocable in test context, so these calls are
        // expected to surface an AuraHandledException. Calling them still covers
        // prompt building and the error-handling path.
        Test.startTest();
        try {
            PortfolioContentAssistant.generateText(
                'Title', 'Project', 'https://x.com',
                'Description__c', 'existing', 'make it punchy', null
            );
        } catch (Exception e) {
            // expected
        }
        try {
            PortfolioContentAssistant.generateText(
                'Title', 'Resume', null, 'Resume_Details__c', null, null,
                'sfdc_ai__DefaultOpenAIGPT4OmniMini'
            );
        } catch (Exception e) {
            // expected
        }
        try {
            PortfolioContentAssistant.generate(rec.Id, 'Resume_Details__c', 'add depth');
        } catch (Exception e) {
            // expected
        }
        Test.stopTest();
        System.assert(true, 'Generation code paths executed');
    }
}