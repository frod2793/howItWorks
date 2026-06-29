using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.TestTools;
using UnityEngine.SceneManagement;
using VContainer;
using Features.InGame;
using Features.Settings;
using System.Reflection;
using Domain.InGame;

public class IntegrationTest
{
    [UnityTest]
    public IEnumerator RunGameFlowTest()
    {
        SceneManager.LoadScene("Title");
        yield return null;

        TitleView titleView = Object.FindFirstObjectByType<TitleView>();
        Assert.IsNotNull(titleView);

        titleView.func_OnNewGameButtonClicked();

        float elapsed = 0f;
        while (SceneManager.GetActiveScene().name != "InGame" && elapsed < 5f)
        {
            elapsed += Time.unscaledDeltaTime;
            yield return null;
        }

        Assert.AreEqual("InGame", SceneManager.GetActiveScene().name);
        yield return new WaitForSeconds(1.0f);

        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        Assert.IsNotNull(scope);
        Assert.IsNotNull(scope.Container);

        IDialogueViewModel dialogueVM = scope.Container.Resolve<IDialogueViewModel>();
        SettingsView settingsView = scope.Container.Resolve<SettingsView>();
        InGameSceneInfoView sceneInfoView = Object.FindFirstObjectByType<InGameSceneInfoView>();

        Assert.IsNotNull(dialogueVM);
        Assert.IsNotNull(settingsView);
        Assert.IsNotNull(sceneInfoView);

        DialogueFlowController controller = scope.Container.Resolve<DialogueFlowController>();
        FieldInfo field = controller.GetType().GetField("m_currentDialogueIndex", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(field);

        int currentIdx = (int)field.GetValue(controller);
        
        int safetyLoop = 0;
        while (currentIdx < 49 && safetyLoop < 100)
        {
            dialogueVM.RequestNext();
            yield return null;
            currentIdx = (int)field.GetValue(controller);
            safetyLoop++;
        }

        Assert.AreEqual(49, currentIdx, "대화 인덱스가 49여야 합니다.");

        dialogueVM.RequestNext();
        yield return null;
        Assert.IsTrue(dialogueVM.IsDisplayingChoices, "대화 49번에서 선택지가 표시되어야 합니다.");

        dialogueVM.SelectChoice(101);
        yield return null;

        currentIdx = (int)field.GetValue(controller);
        Assert.AreEqual(50, currentIdx, "선택지 101번을 누른 뒤에는 대화 인덱스가 50이어야 합니다.");

        safetyLoop = 0;
        while (currentIdx < 55 && safetyLoop < 100)
        {
            dialogueVM.RequestNext();
            yield return null;
            currentIdx = (int)field.GetValue(controller);
            safetyLoop++;
        }

        Assert.AreEqual(55, currentIdx, "대화 인덱스가 55여야 합니다.");

        dialogueVM.RequestNext();
        yield return null;
        Assert.IsTrue(dialogueVM.IsDisplayingChoices, "대화 55번에서 선택지가 표시되어야 합니다.");

        InGameInventorySystem inventorySystem = scope.Container.Resolve<InGameInventorySystem>();
        Assert.IsNotNull(inventorySystem);

        dialogueVM.SelectChoice(201);
        yield return null;

        bool hasItem = inventorySystem.HasItem("ITEM_STRAW_DOLL");
        Assert.IsTrue(hasItem, "짚 인형(ITEM_STRAW_DOLL)이 인벤토리에 들어있어야 합니다.");

        currentIdx = (int)field.GetValue(controller);
        Assert.AreEqual(56, currentIdx, "선택지 201번을 누른 뒤에는 대화 인덱스가 56이어야 합니다.");

        safetyLoop = 0;
        while (currentIdx < 58 && safetyLoop < 100)
        {
            dialogueVM.RequestNext();
            yield return null;
            currentIdx = (int)field.GetValue(controller);
            safetyLoop++;
        }

        Assert.AreEqual(58, currentIdx, "대화 인덱스가 58여야 합니다.");

        dialogueVM.RequestNext();
        yield return null;
        Assert.IsTrue(dialogueVM.IsDisplayingChoices, "대화 58번에서 선택지가 표시되어야 합니다.");

        dialogueVM.SelectChoice(302);
        yield return null;

        currentIdx = (int)field.GetValue(controller);
        Assert.AreEqual(59, currentIdx, "선택지 302번을 누른 뒤에는 대화 인덱스가 59여야 합니다.");

        Assert.IsFalse(settingsView.gameObject.activeSelf, "초기에 설정창은 비활성화 상태여야 합니다.");
        
        sceneInfoView.func_OnSettingsButtonClicked();
        yield return null;

        Assert.IsTrue(settingsView.gameObject.activeSelf, "설정 버튼 클릭 후 설정창이 활성화되어야 합니다.");

        settingsView.func_OnCancelButtonClicked();
        yield return null;

        Assert.IsFalse(settingsView.gameObject.activeSelf, "취소 버튼 클릭 후 설정창이 닫혀야 합니다.");
    }

    [UnityTest]
    public IEnumerator TestSaveLoadLobbyMode()
    {
        SceneManager.LoadScene("Title");
        yield return null;

        TitleLifetimeScope scope = Object.FindFirstObjectByType<TitleLifetimeScope>();
        Assert.IsNotNull(scope);

        SaveLoadView saveLoadView = scope.Container.Resolve<SaveLoadView>();
        ISaveLoadViewModel saveLoadVM = scope.Container.Resolve<ISaveLoadViewModel>();

        Assert.IsNotNull(saveLoadView);
        Assert.IsNotNull(saveLoadVM);

        TitleView titleView = Object.FindFirstObjectByType<TitleView>();
        Assert.IsNotNull(titleView);

        titleView.func_OnLoadGameButtonClicked();
        yield return null;

        Assert.IsTrue(saveLoadView.gameObject.activeSelf);
        Assert.IsFalse(saveLoadVM.IsSaveActionAllowed);

        var saveButtonField = typeof(SaveLoadView).GetField("m_saveButton", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(saveButtonField);
        Button saveButton = saveButtonField.GetValue(saveLoadView) as Button;
        Assert.IsNotNull(saveButton);
        Assert.IsFalse(saveButton.interactable);

        saveLoadView.func_Close();
        yield return null;

        Assert.IsFalse(saveLoadView.gameObject.activeSelf);
    }

    [UnityTest]
    public IEnumerator TestSaveLoadInGameModeAndSave()
    {
        SceneManager.LoadScene("InGame");
        yield return null;

        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        Assert.IsNotNull(scope);

        SaveLoadView saveLoadView = scope.Container.Resolve<SaveLoadView>();
        ISaveLoadViewModel saveLoadVM = scope.Container.Resolve<ISaveLoadViewModel>();

        Assert.IsNotNull(saveLoadView);
        Assert.IsNotNull(saveLoadVM);

        saveLoadView.func_Open(true);
        yield return null;

        Assert.IsTrue(saveLoadView.gameObject.activeSelf);
        Assert.IsTrue(saveLoadVM.IsSaveActionAllowed);

        saveLoadVM.SelectSlot(4);
        yield return null;

        Assert.AreEqual(4, saveLoadVM.SelectedSlotIndex);

        var dummyData = new SaveDataFileDTO();
        dummyData.currentSceneId = "InGame";
        dummyData.globalProgress = new GlobalProgressDataDTO { playthroughCount = 1 };
        dummyData.resources = new ResourceDataDTO { karma = 50, emotion = 10, monitoring = 0, trust = 100 };

        saveLoadVM.ExecuteSave(dummyData);
        yield return null;

        var slotList = saveLoadVM.SlotList;
        Assert.IsNotNull(slotList);
        Assert.AreEqual(5, slotList.Count);
        Assert.IsFalse(string.IsNullOrEmpty(slotList[4].savedAt));

        string savePath = System.IO.Path.Combine(Application.persistentDataPath, "Saves", "save_slot_4.json");
        Assert.IsTrue(System.IO.File.Exists(savePath));

        saveLoadVM.ExecuteDelete();
        yield return null;

        Assert.IsTrue(string.IsNullOrEmpty(slotList[4].savedAt));
        Assert.IsFalse(System.IO.File.Exists(savePath));

        saveLoadView.func_Close();
        yield return null;
    }
}
