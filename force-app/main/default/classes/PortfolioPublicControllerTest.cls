@isTest
private class PortfolioPublicControllerTest {

    @TestSetup
    static void setup() {
        List<Portfolio_Item__c> items = new List<Portfolio_Item__c>{
            new Portfolio_Item__c(
                Name = 'Featured Project',
                Type__c = 'Project',
                Subtitle__c = 'Lead Engineer',
                URL__c = 'https://example.com/proj',
                Secondary_URL__c = 'https://github.com/me/proj',
                Image_URL__c = 'https://example.com/img.png',
                Description__c = 'A featured project.',
                Tech_Stack__c = 'Apex, LWC',
                Start_Date__c = Date.newInstance(2022, 1, 1),
                End_Date__c = Date.newInstance(2023, 1, 1),
                Is_Featured__c = true,
                Active__c = true,
                Sort_Order__c = 2
            ),
            new Portfolio_Item__c(
                Name = 'Plain Bio',
                Type__c = 'Bio',
                Description__c = 'About me.',
                Is_Featured__c = false,
                Active__c = true,
                Sort_Order__c = 1
            ),
            new Portfolio_Item__c(
                Name = 'Hidden Item',
                Type__c = 'Project',
                Active__c = false
            )
        };
        insert items;
    }

    @isTest
    static void returnsOnlyActiveItemsWithFeaturedFirst() {
        Test.startTest();
        List<PortfolioPublicController.Item> result =
            PortfolioPublicController.getPortfolioItems();
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Only active items should return');
        System.assertEquals('Featured Project', result[0].title, 'Featured should sort first');
        System.assertEquals('Lead Engineer', result[0].subtitle, 'Subtitle should map');
        System.assertEquals('https://github.com/me/proj', result[0].secondaryUrl);
        System.assertEquals('https://example.com/img.png', result[0].imageUrl);
        System.assertEquals('Apex, LWC', result[0].techStack);
        System.assertEquals(true, result[0].featured);
        System.assertEquals(Date.newInstance(2022, 1, 1), result[0].startDate);
    }
}