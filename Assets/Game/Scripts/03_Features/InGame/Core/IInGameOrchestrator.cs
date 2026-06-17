using UniTask = Cysharp.Threading.Tasks.UniTask;

namespace Features.InGame
{
    public interface IInGameOrchestrator
    {
        void InitializeGameSession();
        UniTask LoadSceneAsync(int sceneNumber);
        void ProcessNextDialogue();
        void ToggleAutoPlay();
        void ToggleSkip(bool enable);
        void OpenInventory();
        void OpenBacklog();
    }
}
