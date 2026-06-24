@isTest
private class ResumeDetailsProviderTest {

    @isTest
    static void convertsHtmlResumeToText() {
        // Note: the Resume_Details__c Html field sanitizes markup on save
        // (e.g. &nbsp; becomes a non-breaking-space char), so we assert on
        // content that survives that normalization.
        insert new Portfolio_Item__c(
            Name = 'Resume',
            Type__c = 'Resume',
            Resume_Details__c =
                '<p>Hello&nbsp;World</p><b>Skills:</b> Apex &amp; LWC '
                + '&#39;quoted&#39;',
            Active__c = true
        );

        ResumeDetailsProvider.Request req = new ResumeDetailsProvider.Request();
        req.searchKeyword = 'skills';

        Test.startTest();
        List<ResumeDetailsProvider.Result> results =
            ResumeDetailsProvider.getResumeDetails(
                new List<ResumeDetailsProvider.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        ResumeDetailsProvider.Result res = results[0];
        System.assertEquals(true, res.hasData);
        String text = res.resumeDetails;
        System.assert(text.contains('Hello World'), 'nbsp decoded: ' + text);
        System.assert(text.contains('Skills:'), 'tags stripped: ' + text);
        System.assert(text.contains('Apex & LWC'), 'amp decoded: ' + text);
        System.assert(text.contains('\'quoted\''), 'numeric entity decoded: ' + text);
    }

    @isTest
    static void handlesNoResumeContent() {
        insert new Portfolio_Item__c(
            Name = 'Bio Only',
            Type__c = 'Bio',
            Description__c = 'No resume here.',
            Active__c = true
        );

        Test.startTest();
        List<ResumeDetailsProvider.Result> results =
            ResumeDetailsProvider.getResumeDetails(new List<ResumeDetailsProvider.Request>());
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Defaults to one result');
        System.assertEquals(false, results[0].hasData);
    }
}