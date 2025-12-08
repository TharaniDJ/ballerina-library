import ballerina/io;
import ballerina/os;
import ballerinax/github;

// Repository record type
type Repository record {|
    string owner;
    string repo;
    string name;
    string lastVersion;
    string lastChecked;
    string specPath;
    string releaseAssetName;
|};

// Check for version updates
function hasVersionChanged(string oldVersion, string newVersion) returns boolean {
    return oldVersion != newVersion;
}

// Main monitoring function
public function main() returns error? {
    io:println("=== Dependabot OpenAPI Monitor ===");
    io:println("Starting OpenAPI specification monitoring...\n");
    
    // Get GitHub token
    string? token = os:getEnv("GH_TOKEN");
    if token is () {
        io:println("❌ Error: GH_TOKEN environment variable not set");
        io:println("Please set the GH_TOKEN environment variable before running this program.");
        return;
    }
    
    string tokenValue = <string>token;
    
    // Validate token
    if tokenValue.length() == 0 {
        io:println("❌ Error: GH_TOKEN is empty!");
        io:println("The environment variable exists but contains no value.");
        return;
    }
    
    io:println(string `🔍 Token loaded (length: ${tokenValue.length()})`);
    
    // Initialize GitHub client using Ballerina connector
    github:Client githubClient = check new ({
        auth: {
            token: tokenValue
        }
    });
    
    // Sample repositories (will be loaded from repos.json later)
    Repository[] repos = [
        {
            owner: "stripe",
            repo: "openapi",
            name: "Stripe OpenAPI",
            lastVersion: "v0.0.0",
            lastChecked: "2025-01-01T00:00:00Z",
            specPath: "openapi/spec3.yaml",
            releaseAssetName: "spec3.yaml"
        },
        {
            owner: "twilio",
            repo: "twilio-oai",
            name: "Twilio OpenAPI",
            lastVersion: "2.50.0",
            lastChecked: "2025-01-01T00:00:00Z",
            specPath: "twilio_api.json",
            releaseAssetName: "twilio_api.json"
        },
        {
            owner: "openai",
            repo: "openai-openapi",
            name: "OpenAI OpenAPI",
            lastVersion: "1.0.0",
            lastChecked: "2025-01-01T00:00:00Z",
            specPath: "openapi.yaml",
            releaseAssetName: "openapi.yaml"
        }
    ];
    
    io:println(string `Found ${repos.length()} repositories to monitor.\n`);
    
    // Track updates
    Repository[] updatedRepos = [];
    
    // Check each repository
    foreach Repository repo in repos {
        io:println(string `Checking: ${repo.name} (${repo.owner}/${repo.repo})`);
        
        // Get latest release using GitHub connector REST API resource method
        github:Release|error latestRelease = githubClient->/repos/[repo.owner]/[repo.repo]/releases/latest();
        
        if latestRelease is github:Release {
            string tagName = latestRelease.tag_name;
            string? publishedAt = latestRelease.published_at;
            boolean isDraft = latestRelease.draft;
            boolean isPrerelease = latestRelease.prerelease;
            
            if isPrerelease || isDraft {
                io:println(string `  ⏭️  Skipping pre-release: ${tagName}`);
            } else {
                io:println(string `  Latest version: ${tagName}`);
                if publishedAt is string {
                    io:println(string `  Published: ${publishedAt}`);
                }
                
                if hasVersionChanged(repo.lastVersion, tagName) {
                    io:println(string `  ✅ UPDATE AVAILABLE!`);
                    repo.lastVersion = tagName;
                    updatedRepos.push(repo);
                } else {
                    io:println(string `  ℹ️  No updates`);
                }
            }
        } else {
            // Handle errors more gracefully
            string errorMsg = latestRelease.message();
            if errorMsg.includes("404") {
                io:println(string `  ❌ Error: No releases found for ${repo.owner}/${repo.repo}`);
            } else if errorMsg.includes("401") || errorMsg.includes("403") {
                io:println(string `  ❌ Error: Authentication failed`);
                io:println(string `     Check if your GitHub token is valid and has the correct permissions`);
            } else {
                io:println(string `  ❌ Error: ${errorMsg}`);
            }
        }
        
        io:println("");
    }
    
    // Report updates
    if updatedRepos.length() > 0 {
        io:println(string `\n🎉 Found ${updatedRepos.length()} updates:\n`);
        foreach Repository updatedRepo in updatedRepos {
            io:println(string `- ${updatedRepo.name}: ${updatedRepo.lastVersion}`);
        }
        io:println("\n📌 Next steps: Create GitHub issues or notify via Slack");
    } else {
        io:println("✨ All specifications are up-to-date!");
    }
}