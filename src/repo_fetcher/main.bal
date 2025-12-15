import ballerina/io;
import ballerina/os;
import ballerina/file;
import ballerina/time;
import ballerina/http;
import ballerinax/github;

// Simplified registry entry for Phase 1 (GitHub sources only)
type ConnectorRegistry record {|
    string name;
    string display_name;
    string module_version;
    GithubSource github;
    VersionInfo version_info;
    string frequency;
|};

type GithubSource record {|
    string owner;
    string repo;
    string spec_path;
    string release_asset_name;
|};

type VersionInfo record {|
    string last_known_version;  // Release tag like "v2134"
    string last_checked;
|};

// Result of update check
type UpdateResult record {|
    ConnectorRegistry connector;
    string old_version;
    string new_version;
    string release_url;
    string local_path;
|};

// Get the latest release tag from GitHub
function getLatestReleaseTag(github:Client githubClient, string owner, string repo) 
    returns string|error {
    
    io:println(string `  🔍 Fetching latest release from ${owner}/${repo}...`);
    
    // Get latest release
    github:Release release = check githubClient->/repos/[owner]/[repo]/releases/latest();
    
    // Skip pre-releases and drafts
    if release.draft || release.prerelease {
        return error(string `Latest release is ${release.draft ? "draft" : "pre-release"}`);
    }
    
    string tagName = release.tag_name;
    io:println(string `  ✓ Latest release: ${tagName}`);
    return tagName;
}

// Download OpenAPI spec from GitHub release or repository
function downloadSpec(github:Client githubClient, string owner, string repo, 
                     string assetName, string tagName, string specPath, 
                     string localPath) returns error? {
    
    io:println(string `  📥 Downloading ${assetName} from release ${tagName}...`);
    
    string? downloadUrl = ();
    
    // Try to get from release assets first
    github:Release release = check githubClient->/repos/[owner]/[repo]/releases/tags/[tagName]();
    
    github:ReleaseAsset[]? assets = release.assets;
    if assets is github:ReleaseAsset[] {
        foreach github:ReleaseAsset asset in assets {
            if asset.name == assetName {
                downloadUrl = asset.browser_download_url;
                io:println(string `  ✓ Found in release assets`);
                break;
            }
        }
    }
    
    // If not found in assets, get from repository content
    if downloadUrl == "" {
        io:println(string `  ℹ️  Not in release assets, fetching from repository...`);
        
        // Get file content using GitHub API
        github:ContentTree[]? contentArrayResult = check githubClient->/repos/[owner]/[repo]/contents/[specPath]('ref = tagName);
        
        if contentArrayResult is github:ContentTree[] && contentArrayResult.length() > 0 && contentArrayResult[0] is github:ContentFile {
            github:ContentFile content = <github:ContentFile>contentArrayResult[0];
            // Decode base64 content
            string? encodedContent = content.content;
            if encodedContent is string {
                // Use download_url instead of decoding base64
                downloadUrl = content.download_url;
            }
        }
    }
    
    if downloadUrl is () {
        return error(string `Could not find ${assetName} in release or repository`);
    }
    
    // Download using GitHub client
    github:Client httpClient = check new ({
        auth: {
            token: <string>os:getEnv("GH_TOKEN")
        }
    });
    
    // Note: For actual file download, we need to use http:Client
    // But we'll construct the raw URL and download it
    string rawUrl = string `https://raw.githubusercontent.com/${owner}/${repo}/${tagName}/${specPath}`;
    
    // Download the content directly using HTTP
    if downloadUrl == "" {
        return error("No download URL available");
    }
    
    string url = downloadUrl;
    http:Client downloadClient = check new ("");
    http:Response response = check downloadClient->get(url);
    
    if response.statusCode != 200 {
        return error(string `HTTP ${response.statusCode}: Failed to download file`);
    }
    
    byte[] content = check response.getBinaryPayload();
    
    // Create directory if it doesn't exist
    string dirPath = check file:parentPath(localPath);
    if !check file:test(dirPath, file:EXISTS) {
        check file:createDir(dirPath, file:RECURSIVE);
    }
    
    // Write to file
    check io:fileWriteBytes(localPath, content);
    io:println(string `  ✅ Downloaded to ${localPath}`);
    return;
}

// Map connector name to api-specs directory structure
function getApiSpecsPath(string connectorName, string specPath) returns string {
    // Extract vendor and API name from connector name
    // e.g., "module-ballerinax-stripe" -> "stripe/stripe"
    // e.g., "module-ballerinax-docusign.dsadmin" -> "docusign/admin"
    
    string cleanName = connectorName.substring(18); // Remove "module-ballerinax-"
    
    string[] parts = re `\.`.split(cleanName);
    string vendor = parts[0];
    string apiName = parts.length() > 1 ? parts[1] : parts[0];
    
    // Determine file name from spec_path
    string fileName = "openapi.yaml";
    if specPath.endsWith(".json") {
        fileName = "openapi.json";
    }
    
    return string `openapi/${vendor}/${apiName}/latest/${fileName}`;
}

// Get current timestamp in ISO format
function getCurrentTimestamp() returns string {
    time:Utc currentTime = time:utcNow();
    return time:utcToString(currentTime);
}

// Main monitoring function
public function main() returns error? {
    io:println("╔═══════════════════════════════════════════════════════════╗");
    io:println("║   Ballerina OpenAPI Dependabot - Version Checker         ║");
    io:println("║   Phase 1: GitHub Release Tags                            ║");
    io:println("╚═══════════════════════════════════════════════════════════╝\n");
    
    // Get GitHub token
    string? token = os:getEnv("GH_TOKEN");
    if token is () {
        io:println("❌ Error: GH_TOKEN environment variable not set");
        io:println("Please set: export GH_TOKEN=\"your_token_here\"");
        return error("Missing GitHub token");
    }
    
    io:println("🔑 GitHub token loaded\n");
    
    // Initialize GitHub client
    github:Client githubClient = check new ({
        auth: {
            token: <string>token
        }
    });
    
    // Load registry
    json registryJson = check io:fileReadJson("registry_phase1.json");
    ConnectorRegistry[] connectors = check registryJson.cloneWithType();
    
    io:println(string `📋 Loaded ${connectors.length()} connectors to monitor\n`);
    
    // Track updates
    UpdateResult[] updates = [];
    int checkedCount = 0;
    int errorCount = 0;
    
    // Check each connector
    foreach ConnectorRegistry connector in connectors {
        io:println(string `━━━ ${connector.display_name} ━━━`);
        io:println(string `    Repository: ${connector.github.owner}/${connector.github.repo}`);
        
        checkedCount += 1;
        
        // Get latest release tag
        string|error latestTag = getLatestReleaseTag(
            githubClient,
            connector.github.owner,
            connector.github.repo
        );
        
        if latestTag is error {
            io:println(string `  ❌ Error: ${latestTag.message()}`);
            errorCount += 1;
            io:println("");
            continue;
        }
        
        string currentVersion = connector.version_info.last_known_version;
        
        // Check if version changed
        if currentVersion == "" || currentVersion != latestTag {
            if currentVersion == "" {
                io:println("  🆕 New connector (no previous version tracked)");
            } else {
                io:println("  ✅ UPDATE DETECTED!");
                io:println(string `     Old: ${currentVersion}`);
                io:println(string `     New: ${latestTag}`);
            }
            
            // Determine local path in api-specs repo
            string localPath = getApiSpecsPath(connector.name, connector.github.spec_path);
            string fullPath = string `../api-specs/${localPath}`;
            
            // Download the spec
            error? downloadResult = downloadSpec(
                githubClient,
                connector.github.owner,
                connector.github.repo,
                connector.github.release_asset_name,
                latestTag,
                connector.github.spec_path,
                fullPath
            );
            
            if downloadResult is error {
                io:println(string `  ❌ Download failed: ${downloadResult.message()}`);
                errorCount += 1;
            } else {
                // Track successful update
                updates.push({
                    connector: connector,
                    old_version: currentVersion,
                    new_version: latestTag,
                    release_url: string `https://github.com/${connector.github.owner}/${connector.github.repo}/releases/tag/${latestTag}`,
                    local_path: localPath
                });
                
                // Update the connector record
                connector.version_info.last_known_version = latestTag;
                connector.version_info.last_checked = getCurrentTimestamp();
            }
        } else {
            io:println(string `  ℹ️  Up to date (${currentVersion})`);
        }
        
        io:println("");
    }
    
    // Summary
    io:println("╔═══════════════════════════════════════════════════════════╗");
    io:println("║                         SUMMARY                           ║");
    io:println("╚═══════════════════════════════════════════════════════════╝");
    io:println(string `Checked:  ${checkedCount} connectors`);
    io:println(string `Updates:  ${updates.length()} found`);
    io:println(string `Errors:   ${errorCount}`);
    io:println("");
    
    if updates.length() > 0 {
        io:println("📋 Updated Connectors:");
        foreach UpdateResult update in updates {
            string oldDisplay = update.old_version == "" ? "NEW" : update.old_version;
            io:println(string `  • ${update.connector.display_name}: ${oldDisplay} → ${update.new_version}`);
        }
        
        // Save updated registry
        check io:fileWriteJson("registry_phase1.json", connectors.toJson());
        io:println("\n✅ Updated registry_phase1.json with new release tags");
        
        // Create update summary for PR
        string[] updateLines = [];
        updateLines.push("# OpenAPI Specification Updates\n");
        updateLines.push(string `Updated ${updates.length()} specification(s) based on latest GitHub releases:\n`);
        
        foreach UpdateResult update in updates {
            string oldDisplay = update.old_version == "" ? "NEW" : update.old_version;
            updateLines.push("\n## " + update.connector.display_name);
            updateLines.push("- **Location**: `" + update.local_path + "`");
            updateLines.push("- **Previous Version**: " + oldDisplay);
            updateLines.push("- **Current Version**: " + update.new_version);
            updateLines.push("- **Release**: " + update.release_url);
        }
        
        string summary = string:'join("\n", ...updateLines);
        check io:fileWriteString("UPDATE_SUMMARY.md", summary);
        
        io:println("\n📝 Created UPDATE_SUMMARY.md");
        io:println("\n📌 Next Steps:");
        io:println("   1. Review changes in ../api-specs/");
        io:println("   2. Create PR using: ./scripts/create-pr.sh");
    } else {
        io:println("✨ All specifications are up-to-date!");
    }
    
    return;
}