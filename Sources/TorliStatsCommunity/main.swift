import Darwin
import TorliStats

if AppUpdateInstaller.runHelperIfRequested() {
    exit(EXIT_SUCCESS)
}
TorliApplication.run()
