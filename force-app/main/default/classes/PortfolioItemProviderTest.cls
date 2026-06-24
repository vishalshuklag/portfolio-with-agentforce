@isTest
private class PortfolioItemProviderTest {

    @TestSetup
    static void setup() {
        insert new List<Portfolio_Item__c>{
            new Portfolio_Item__c(
                Name = 'Current Role',
                Type__c = 'Experience',
                Subtitle__c = 'Architect at Acme',
                Description__c = 'Building things.',
                Start_Date__c = Date.newInstance(2022, 1, 5),
                Active__c = true,
                Sort_Order__c = 1
            ),
            new Portfolio_Item__c(
                Name = 'Past Role',
                Type__c = 'Experience',
                Start_Date__c = Date.newInstance(2019, 3, 1),
                End_Date__c = Date.newInstance(2021, 12, 1),
                Active__c = true,
                Sort_Order__c = 2
            ),
            new Portfolio_Item__c(
                Name = 'My Blog',
                Type__c = 'Blog',
                URL__c = 'https://blog.example.com',
                Active__c = true,
                Sort_Order__c = 3
            )
        };
    }

    @isTest
    static void filtersByTypeAndFormatsTimeframe() {
        PortfolioItemProvider.Request req = new PortfolioItemProvider.Request();
        req.itemType = 'Experience';

        Test.startTest();
        List<PortfolioItemProvider.Result> results =
            PortfolioItemProvider.getItems(new List<PortfolioItemProvider.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        PortfolioItemProvider.Result res = results[0];
        System.assertEquals(true, res.hasData);
        System.assertEquals(2, res.items.size(), 'Only Experience items');

        Map<String, String> timeframeByTitle = new Map<String, String>();
        for (PortfolioItemProvider.PortfolioItem item : res.items) {
            timeframeByTitle.put(item.title, item.timeframe);
        }
        System.assertEquals('Jan 2022 - Present', timeframeByTitle.get('Current Role'));
        System.assertEquals('Mar 2019 - Dec 2021', timeframeByTitle.get('Past Role'));
    }

    @isTest
    static void blankFilterReturnsAll() {
        PortfolioItemProvider.Request req = new PortfolioItemProvider.Request();
        req.itemType = null;

        Test.startTest();
        List<PortfolioItemProvider.Result> results =
            PortfolioItemProvider.getItems(new List<PortfolioItemProvider.Request>{ req });
        Test.stopTest();

        System.assertEquals(3, results[0].items.size(), 'All active items return');
    }

    @isTest
    static void tolerantMatchHandlesPluralAndPartialTypes() {
        PortfolioItemProvider.Request plural = new PortfolioItemProvider.Request();
        plural.itemType = 'Experiences'; // plural of stored "Experience"

        PortfolioItemProvider.Request partial = new PortfolioItemProvider.Request();
        partial.itemType = 'blogs'; // plural / different case of stored "Blog"

        PortfolioItemProvider.Request missing = new PortfolioItemProvider.Request();
        missing.itemType = 'YouTube'; // nothing stored for this category

        Test.startTest();
        List<PortfolioItemProvider.Result> results =
            PortfolioItemProvider.getItems(new List<PortfolioItemProvider.Request>{
                plural, partial, missing
            });
        Test.stopTest();

        System.assertEquals(2, results[0].items.size(), '"Experiences" matches Experience items');
        System.assertEquals(1, results[1].items.size(), '"blogs" matches the Blog item');
        System.assertEquals(false, results[2].hasData, '"YouTube" matches nothing -> no data');
    }

    @isTest
    static void typeMatchGuardsAgainstShortTokens() {
        System.assertEquals(true, PortfolioItemProvider.typeMatches('Certification', 'certifications'));
        System.assertEquals(true, PortfolioItemProvider.typeMatches('Certification', 'cert'));
        System.assertEquals(true, PortfolioItemProvider.typeMatches('Project', 'projects'));
        System.assertEquals(false, PortfolioItemProvider.typeMatches('Certification', 'ai'),
            'Tokens shorter than 3 chars must not match');
        System.assertEquals(false, PortfolioItemProvider.typeMatches('Experience', 'education'));
        System.assertEquals(false, PortfolioItemProvider.typeMatches(null, 'bio'));
    }
}