#import <ARChromeActivity/ARChromeActivity.h>
#import <AVFoundation/AVFoundation.h>
#import <PureLayout/PureLayout.h>
#import <SafariServices/SafariServices.h>
#import <TUSafariActivity/TUSafariActivity.h>
#import <Tweaks/FBTweakInline.h>
#import <WebKit/WebKit.h>

#import "MMMPostDetailViewController.h"
#import "MMMPost.h"

static NSString * const MMMBaseURL = @"macmagazine.com.br";
static NSString * const MMMUserAgent = @"MacMagazine";

typedef NS_ENUM(NSUInteger, MMMLinkClickType) {
    MMMLinkClickTypeInternal,
    MMMLinkClickTypeExternal,
};

@interface MMMPostDetailViewController () <WKNavigationDelegate>

@property (nonatomic, weak) WKWebView *webView;

@end

#pragma mark MMMPostDetailViewController

@implementation MMMPostDetailViewController

#pragma mark - Class Methods

#pragma mark - Getters/Setters

#pragma mark - Actions

- (void)pushToNewDetailViewControllerWithURL:(NSURL *)URL {
    MMMPostDetailViewController *destinationViewController = [[self storyboard] instantiateViewControllerWithIdentifier:NSStringFromClass([self class])];
    destinationViewController.postURL = URL;
    destinationViewController.post = nil;
    [self.navigationController pushViewController:destinationViewController animated:YES];
}

- (void)pushToSFSafariViewControllerWithURL:(NSURL *)URL {
    SFSafariViewController *safariViewController = [[SFSafariViewController alloc] initWithURL:URL];
    [self presentViewController:safariViewController animated:YES completion:nil];
}

#pragma mark - Button Actions

- (void)actionButtonTapped:(id)sender {
    if (!self.webView.URL) {
        return;
    }

    UIBarButtonItem *actionItem = (UIBarButtonItem *)sender;
    NSMutableArray *activityItems = [[NSMutableArray alloc] init];
    if (self.post) {
        [activityItems addObject:self.post.title];
    }
    [activityItems addObject:self.webView.URL];

    NSMutableArray<__kindof UIActivity *> *browserActivities = [[NSMutableArray alloc] init];
    [browserActivities addObject:[[TUSafariActivity alloc] init]];

    NSURL *chromeURLScheme = [NSURL URLWithString:@"googlechrome-x-callback://"];
    if ([[UIApplication sharedApplication] canOpenURL:chromeURLScheme]) {
        ARChromeActivity *chromeActivity = [[ARChromeActivity alloc] init];
        chromeActivity.activityTitle = NSLocalizedString(@"Post.Sharing.OpenInChrome", @"");
        [browserActivities addObject:chromeActivity];
    }

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:activityItems
                                                                                         applicationActivities:browserActivities];
    activityViewController.modalPresentationStyle = UIModalPresentationPopover;
    activityViewController.popoverPresentationController.barButtonItem = actionItem;
    [self presentViewController:activityViewController animated:YES completion:nil];
}

#pragma mark - Instance Methods

- (void)setupWebView {
    WKWebView *webView = [[WKWebView alloc] init];
    [self.view addSubview:webView];
    self.webView = webView;
    [self.webView autoPinEdgesToSuperviewEdges];

    // Changes the WKWebView user agent in order to hide some CSS/HTML elements
    self.webView.customUserAgent = MMMUserAgent;
    self.webView.navigationDelegate = self;

    // Observer to check that loading has completelly finished for the WebView
    [self.webView addObserver:self forKeyPath:@"loading" options:NSKeyValueObservingOptionNew context:NULL];


    // Loads the request for the post URL
    if (!self.postURL) {
        self.postURL = [NSURL URLWithString:self.post.link];
    }

    NSURL *URL = self.postURL;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:60];
    [self.webView loadRequest:request];
}

- (void)reloadViewControllerWithPost:(MMMPost *)post {
    [self.webView stopLoading];

    self.post = post;
    self.postURL = nil;

    [self setupWebView];
    [self setupNavigationBar];
}

- (void)setupNavigationBar {
    UIBarButtonItem *rightItem;

    if (self.webView.isLoading) {
        UIActivityIndicatorView *activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        [activityView setFrame:CGRectMake(0, 0, 20.0f, 20.0f)];
        [activityView startAnimating];
        rightItem = [[UIBarButtonItem alloc] initWithCustomView:activityView];
    } else {
        // Action item
        rightItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                  target:self
                                                                  action:@selector(actionButtonTapped:)];
    }

    self.navigationItem.rightBarButtonItem = rightItem;
}

- (void)performActionForLinkClickWithType:(MMMLinkClickType)linkClickType URL:(NSURL *)URL {
    if (linkClickType == MMMLinkClickTypeInternal) {
        [self pushToNewDetailViewControllerWithURL:URL];
    } else if (linkClickType == MMMLinkClickTypeExternal) {
        [self pushToSFSafariViewControllerWithURL:URL];
    }
}

#pragma mark - Protocols

#pragma makr - WKWebView KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{
    if ([keyPath isEqualToString:@"loading"] && object == self.webView) {
        // Update the right item on the navbar acordingly
        [self setupNavigationBar];
    }
}

#pragma mark - WKNavigationDelegate Delegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    WKNavigationActionPolicy actionPolicy = WKNavigationActionPolicyAllow;
    NSURL *targetURL = navigationAction.request.URL;

    MMMLinkClickType linkClickType = ([targetURL.absoluteString containsString:MMMBaseURL]) ? MMMLinkClickTypeInternal : MMMLinkClickTypeExternal;

    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        [self performActionForLinkClickWithType:linkClickType URL:targetURL];

        actionPolicy = WKNavigationActionPolicyCancel;
    } else if (navigationAction.navigationType == WKNavigationTypeOther) {
        // Semi-hack sollution to capture URL selection when there's a javascript redirect.
        // http://tech.vg.no/2013/09/13/dissecting-javascript-clicks-in-uiwebview/

        // For javascript-triggered links
        NSString *documentURL = [[navigationAction.request mainDocumentURL] absoluteString];

        // If they are the same this is a javascript href click
        if ([targetURL.absoluteString isEqualToString:documentURL]) {
            if (!self.webView.isLoading) {
                [self performActionForLinkClickWithType:linkClickType URL:targetURL];

                actionPolicy = WKNavigationActionPolicyCancel;
            }
        }
    }

    decisionHandler(actionPolicy);
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    [self reloadViewControllerWithPost:self.post];
}

- (void)dealloc {
    [self.webView removeObserver:self forKeyPath:@"loading"];
}

@end
