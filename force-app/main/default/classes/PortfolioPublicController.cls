/**
 * Read-only controller for the public-facing portfolioHome LWC.
 * Returns the site owner's active Portfolio_Item__c records so guest visitors
 * on an Experience Cloud site can see what's available and chat with the agent.
 * Runs `with sharing` and exposes only display-safe fields.
 */
public with sharing class PortfolioPublicController {

    public class Item {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String type;
        @AuraEnabled public String url;
        @AuraEnabled public String secondaryUrl;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String description;
        @AuraEnabled public String techStack;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Boolean featured;
    }

    @AuraEnabled(cacheable=true)
    public static List<Item> getPortfolioItems() {
        List<Item> result = new List<Item>();
        for (Portfolio_Item__c record : [
            SELECT Id, Name, Subtitle__c, Type__c, URL__c, Secondary_URL__c,
                   Image_URL__c, Description__c, Tech_Stack__c,
                   Start_Date__c, End_Date__c, Is_Featured__c
            FROM Portfolio_Item__c
            WHERE Active__c = true
            ORDER BY Is_Featured__c DESC, Sort_Order__c ASC NULLS LAST,
                     Start_Date__c DESC NULLS LAST, Name ASC
            LIMIT 200
        ]) {
            Item item = new Item();
            item.id = record.Id;
            item.title = record.Name;
            item.subtitle = record.Subtitle__c;
            item.type = record.Type__c;
            item.url = record.URL__c;
            item.secondaryUrl = record.Secondary_URL__c;
            item.imageUrl = record.Image_URL__c;
            item.description = record.Description__c;
            item.techStack = record.Tech_Stack__c;
            item.startDate = record.Start_Date__c;
            item.endDate = record.End_Date__c;
            item.featured = record.Is_Featured__c;
            result.add(item);
        }
        return result;
    }
}