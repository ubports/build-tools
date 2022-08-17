import org.jenkinsci.plugins.workflow.support.steps.build.RunWrapper

def call(
  RunWrapper currentBuild,
  String jobDescription,
  String jobUrl
) {
  String status;
  Boolean needUrl = false;

  switch (currentBuild.currentResult) {
    case "SUCCESS":
      if (currentBuild?.getPreviousBuild()?.resultIsWorseOrEqualTo("UNSTABLE"))
        status = "**FIXED**";
      else
        status = "**SUCCESS**";

      break;

    case "UNSTABLE":
      status = "**UNSTABLE**";
      needUrl = true;
      break;

    case "FAILURE":
      if (currentBuild?.getPreviousBuild()?.resultIsWorseOrEqualTo("FAILURE"))
        status = "**NOT FIXED**";
      else
        status = "**FAILURE**";

      needUrl = true;
      break;
  }

  notifyTelegram("${jobDescription}: ${status}${needUrl ? ", check ${jobUrl}" : ""}");
}
