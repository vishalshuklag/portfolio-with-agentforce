@isTest
private class PortfolioOverviewProviderTest {
  @TestSetup
  static void setup() {
    insert new List<Portfolio_Item__c>{
      new Portfolio_Item__c(
        Name = 'Visha',
        Type__c = 'Bio',
        Active__c = true,
        Sort_Order__c = 1
      ),
      new Portfolio_Item__c(
        Name = 'Current Role',
        Type__c = 'Experience',
        Active__c = true,
        Sort_Order__c = 2
      ),
      new Portfolio_Item__c(
        Name = 'Past Role',
        Type__c = 'Experience',
        Active__c = true,
        Sort_Order__c = 3
      ),
      new Portfolio_Item__c(
        Name = 'Cert A',
        Type__c = 'Certification',
        Active__c = true,
        Sort_Order__c = 4
      ),
      new Portfolio_Item__c(
        Name = 'Cert B',
        Type__c = 'Certification',
        Active__c = true,
        Sort_Order__c = 5
      ),
      new Portfolio_Item__c(
        Name = 'Cert C',
        Type__c = 'Certification',
        Active__c = true,
        Sort_Order__c = 6
      ),
      new Portfolio_Item__c(
        Name = 'My Blog',
        Type__c = 'Blog',
        URL__c = 'https://blog.example.com',
        Active__c = true,
        Sort_Order__c = 7
      ),
      new Portfolio_Item__c(
        Name = 'Hidden',
        Type__c = 'Bio',
        Active__c = false,
        Sort_Order__c = 8
      )
    };
  }

  @isTest
  static void summarizesActiveCategoriesWithCounts() {
    Test.startTest();
    List<PortfolioOverviewProvider.Result> results = PortfolioOverviewProvider.getOverview(
      new List<PortfolioOverviewProvider.Request>{
        new PortfolioOverviewProvider.Request()
      }
    );
    Test.stopTest();

    System.assertEquals(1, results.size());
    PortfolioOverviewProvider.Result res = results[0];
    System.assertEquals(true, res.hasData);

    Map<String, Integer> countByType = new Map<String, Integer>();
    Map<String, String> examplesByType = new Map<String, String>();
    for (PortfolioOverviewProvider.Category cat : res.categories) {
      countByType.put(cat.itemType, cat.count);
      examplesByType.put(cat.itemType, cat.examples);
    }

    System.assertEquals(
      4,
      res.categories.size(),
      'Four active categories: Bio, Experience, Certification, Blog'
    );
    System.assertEquals(1, countByType.get('Bio'), 'Inactive Bio excluded');
    System.assertEquals(2, countByType.get('Experience'));
    System.assertEquals(3, countByType.get('Certification'));
    System.assertEquals(1, countByType.get('Blog'));

    // Examples are populated and capped at three.
    System.assert(
      examplesByType.get('Experience').contains('Current Role'),
      'Examples include item titles: ' + examplesByType.get('Experience')
    );

    // Summary contains each category with its count and correct pluralization.
    System.assert(
      res.summary.contains('Certification (3 items)'),
      'Summary: ' + res.summary
    );
    System.assert(
      res.summary.contains('Experience (2 items)'),
      'Summary: ' + res.summary
    );
    System.assert(
      res.summary.contains('Bio (1 item)'),
      'Summary: ' + res.summary
    );
    System.assert(
      res.summary.contains('Blog (1 item)'),
      'Summary: ' + res.summary
    );

    // Preferred ordering: Bio before Experience before Certification before Blog.
    System.assert(
      res.summary.indexOf('Bio') < res.summary.indexOf('Experience') &&
        res.summary.indexOf('Experience') <
        res.summary.indexOf('Certification') &&
        res.summary.indexOf('Certification') < res.summary.indexOf('Blog'),
      'Ordered summary: ' + res.summary
    );
  }

  @isTest
  static void handlesEmptyPortfolio() {
    delete [SELECT Id FROM Portfolio_Item__c];

    Test.startTest();
    List<PortfolioOverviewProvider.Result> results = PortfolioOverviewProvider.getOverview(
      new List<PortfolioOverviewProvider.Request>()
    );
    Test.stopTest();

    System.assertEquals(
      1,
      results.size(),
      'Defaults to one result when no requests'
    );
    System.assertEquals(false, results[0].hasData);
    System.assertEquals(0, results[0].categories.size());
    System.assert(
      results[0].summary.contains('no items'),
      'Summary: ' + results[0].summary
    );
  }
}
