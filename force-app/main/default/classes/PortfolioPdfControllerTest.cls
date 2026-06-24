@isTest
private class PortfolioPdfControllerTest {

    private static Portfolio_Item__c item(String name, String type) {
        return new Portfolio_Item__c(Name = name, Type__c = type, Active__c = true);
    }

    /**
     * Inserts at least one record for every category the page renders and
     * asserts the generated PDF HTML mirrors those sections — the PDF should
     * stay in lockstep with portfolioHome.
     */
    @isTest
    static void rendersEveryPageSection() {
        Portfolio_Item__c bio = item('Jane Doe', 'Bio');
        bio.Description__c = 'Senior engineer and builder.';

        Portfolio_Item__c featured = item('Flagship Platform', 'Project');
        featured.Is_Featured__c = true;
        featured.Description__c = 'A featured highlight.';

        Portfolio_Item__c exp = item('Lead Engineer', 'Experience');
        exp.Subtitle__c = 'Acme';
        exp.Start_Date__c = Date.newInstance(2018, 1, 1);

        Portfolio_Item__c edu = item('B.S. Computer Science', 'Education');
        edu.Subtitle__c = 'State University';

        Portfolio_Item__c proj = item('Cool App', 'Project');
        proj.Tech_Stack__c = 'Apex, LWC';
        proj.URL__c = 'https://example.com/app';
        proj.Secondary_URL__c = 'https://github.com/jane/app';

        Portfolio_Item__c cert = item('AI Associate', 'Certification');
        cert.Subtitle__c = 'Salesforce';

        Portfolio_Item__c blog = item('My Blog Post', 'Blog');
        blog.URL__c = 'https://blog.example.com/post';

        Portfolio_Item__c video = item('Conference Talk', 'YouTube');
        video.URL__c = 'https://youtu.be/abcdefghijk';

        Portfolio_Item__c linkedIn = item('LinkedIn', 'LinkedIn');
        linkedIn.URL__c = 'https://linkedin.com/in/jane';

        Portfolio_Item__c github = item('GitHub', 'GitHub');
        github.URL__c = 'https://github.com/jane';

        Portfolio_Item__c website = item('Personal Site', 'Website');
        website.URL__c = 'https://jane.dev';

        Portfolio_Item__c skill = item('Apex', 'Skill');
        skill.Subtitle__c = 'Backend';

        Portfolio_Item__c aiTool = item('Cursor', 'AI Tool');
        aiTool.Description__c = 'Pair programming.';

        Portfolio_Item__c service = item('Consulting', 'Service');
        service.Description__c = 'Architecture reviews.';

        Portfolio_Item__c now = item('Building an agent', 'Now');
        now.Description__c = 'Currently focused on Agentforce.';

        Portfolio_Item__c lang = item('English', 'Language');
        lang.Subtitle__c = 'Native';

        Portfolio_Item__c award = item('MVP', 'Award');
        award.Start_Date__c = Date.newInstance(2023, 1, 1);

        Portfolio_Item__c endorsement = item('John Smith', 'Endorsement');
        endorsement.Description__c = 'Fantastic to work with.';
        endorsement.Subtitle__c = 'CTO, BigCo';

        Portfolio_Item__c community = item('Trailblazer Mentor', 'Community');
        community.Description__c = 'Mentoring newcomers.';

        Portfolio_Item__c volunteer = item('Food Bank', 'Volunteering');
        volunteer.Description__c = 'Weekend shifts.';

        Portfolio_Item__c interest = item('Photography', 'Interest');
        interest.Description__c = 'Landscapes.';

        Portfolio_Item__c other = item('Fun Fact', 'Other');
        other.Description__c = 'Catch-all item.';

        Portfolio_Item__c inactive = item('Hidden Project', 'Project');
        inactive.Active__c = false;

        insert new List<Portfolio_Item__c>{
            bio, featured, exp, edu, proj, cert, blog, video, linkedIn, github,
            website, skill, aiTool, service, now, lang, award, endorsement,
            community, volunteer, interest, other, inactive
        };

        Test.startTest();
        PortfolioPdfController ctrl = new PortfolioPdfController();
        String base64 = PortfolioPdfController.generatePdfBase64(
            'Jane Doe', 'Salesforce Engineer', 'I build things on the platform.', 'Remote'
        );
        Test.stopTest();

        System.assertEquals('Jane Doe', ctrl.ownerName, 'owner derived from Bio');
        System.assertEquals('JD', ctrl.initials, 'initials from owner name');
        System.assert(String.isNotBlank(base64), 'returns base64 content');

        String html = EncodingUtil.base64Decode(base64).toString();

        // Header context from the LWC overrides
        System.assert(html.contains('Salesforce Engineer'), 'role eyebrow rendered');
        System.assert(html.contains('Jane Doe'), 'owner name rendered');
        System.assert(html.contains('I build things on the platform.'), 'tagline rendered');
        System.assert(html.contains('Remote'), 'location rendered');

        // Every section title (mirrors portfolioHome.html)
        for (String title : new List<String>{
            'Years experience', 'About', 'Skills', 'AI usage', 'Services',
            'Featured', 'Projects', 'Experience', 'Education', 'Certifications',
            'Awards &amp; rewards', 'Endorsements', 'Community contributions',
            'Volunteering', 'Writing &amp; talks', 'Videos', 'Languages',
            'Interests', 'Profiles &amp; links', 'More'
        }) {
            System.assert(html.contains(title), 'section present: ' + title);
        }

        // Content details
        System.assert(html.contains('Apex'), 'project tech tag rendered');
        System.assert(html.contains('Fantastic to work with.'), 'endorsement quote rendered');
        System.assert(!html.contains('Hidden Project'), 'inactive item excluded');
    }

    @isTest
    static void defaultsOwnerFromBioWhenNoOverride() {
        Portfolio_Item__c bio = item('John Q. Public', 'Bio');
        bio.Description__c = 'Hello there.';
        insert bio;

        Test.startTest();
        PortfolioPdfController ctrl = new PortfolioPdfController();
        String base64 = PortfolioPdfController.generatePdfBase64(null, null, null, null);
        Test.stopTest();

        System.assertEquals('John Q. Public', ctrl.ownerName, 'owner falls back to Bio name');
        System.assertEquals('JP', ctrl.initials);
        System.assertEquals('Hello there.', ctrl.tagline, 'tagline falls back to Bio summary');
        System.assertEquals(null, ctrl.roleTitle);
        System.assert(String.isNotBlank(base64));
    }

    @isTest
    static void fallbackLabelWhenNoBio() {
        insert item('Some Project', 'Project');

        Test.startTest();
        PortfolioPdfController ctrl = new PortfolioPdfController();
        String base64 = PortfolioPdfController.generatePdfBase64(null, null, null, null);
        Test.stopTest();

        System.assertEquals('My Portfolio', ctrl.ownerName, 'fallback label when no Bio');
        String html = EncodingUtil.base64Decode(base64).toString();
        System.assert(html.contains('Projects'), 'projects section still renders');
        System.assert(!html.contains('>About<'), 'no About section without a Bio');
    }

    @isTest
    static void classifyMirrorsPageLogic() {
        System.assertEquals('video', PortfolioPdfController.classify('YouTube'));
        System.assertEquals('video', PortfolioPdfController.classify('Video'));
        System.assertEquals('linkedin', PortfolioPdfController.classify('LinkedIn'));
        System.assertEquals('github', PortfolioPdfController.classify('GitHub'));
        System.assertEquals('bio', PortfolioPdfController.classify('Bio'));
        System.assertEquals('endorsement', PortfolioPdfController.classify('Testimonial'));
        System.assertEquals('aitool', PortfolioPdfController.classify('AI Tool'));
        System.assertEquals('skill', PortfolioPdfController.classify('Skill'));
        System.assertEquals('service', PortfolioPdfController.classify('Service'));
        System.assertEquals('now', PortfolioPdfController.classify('Now'));
        System.assertEquals('language', PortfolioPdfController.classify('Language'));
        System.assertEquals('award', PortfolioPdfController.classify('Award'));
        System.assertEquals('volunteering', PortfolioPdfController.classify('Volunteering'));
        System.assertEquals('community', PortfolioPdfController.classify('Community'));
        System.assertEquals('interest', PortfolioPdfController.classify('Interest'));
        System.assertEquals('project', PortfolioPdfController.classify('Project'));
        System.assertEquals('experience', PortfolioPdfController.classify('Experience'));
        System.assertEquals('education', PortfolioPdfController.classify('Education'));
        System.assertEquals('certification', PortfolioPdfController.classify('Certification'));
        System.assertEquals('website', PortfolioPdfController.classify('Website'));
        System.assertEquals('writing', PortfolioPdfController.classify('Blog'));
        System.assertEquals('other', PortfolioPdfController.classify('Something Else'));
        System.assertEquals('other', PortfolioPdfController.classify(null));
    }

    @isTest
    static void computeInitialsHandlesEdgeCases() {
        System.assertEquals('JD', PortfolioPdfController.computeInitials('Jane Doe'));
        System.assertEquals('M', PortfolioPdfController.computeInitials('Madonna'));
        System.assertEquals('\u2605', PortfolioPdfController.computeInitials(null));
        System.assertEquals('\u2605', PortfolioPdfController.computeInitials('   '));
    }
}