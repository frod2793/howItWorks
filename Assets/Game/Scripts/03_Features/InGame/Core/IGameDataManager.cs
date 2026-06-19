using System.Collections.Generic;
using Cysharp.Threading.Tasks;
using Domain.InGame;

namespace Features.InGame
{
    public interface IGameDataManager
    {
        UniTask LoadAllDataAsync();
        
        SaveDataFileDTO GetSaveData();
        List<CharacterDTO> GetCharacters();
        List<SceneDTO> GetScenes();
        List<BranchDTO> GetBranches();
        List<ActOptionDTO> GetActMenu();
        List<InventoryItemDTO> GetInventory();
        List<GameModuleDTO> GetModules();
        List<DialogueLineDTO> GetDialogueLog();
        GameSettingsDTO GetSettings();
        List<AchievementDTO> GetAchievements();
        List<EmotionTrendRowDTO> GetEmotionTrends();
        List<PlaythroughLogRowDTO> GetPlaythroughLogs();
        List<BranchMatrixDTO> GetBranchMatrix();
        List<SubplotDTO> GetSubplots();
        List<LoopVariationDTO> GetLoopVariations();
        List<ChoiceTriggerDTO> GetChoiceTriggers();
    }
}
