using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.SceneManagement;
using VContainer;
using Features.InGame;
using Features.Settings;
using System.Reflection;

public class IntegrationTest
{
    [UnityTest]
    public IEnumerator RunGameFlowTest()
    {
        SceneManager.LoadScene("Title");
        yield return null;

        TitleView titleView = Object.FindObjectOfType<TitleView>();
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

        InGameLifetimeScope scope = Object.FindObjectOfType<InGameLifetimeScope>();
        Assert.IsNotNull(scope);
        Assert.IsNotNull(scope.Container);

        IDialogueViewModel dialogueVM = scope.Container.Resolve<IDialogueViewModel>();
        SettingsView settingsView = scope.Container.Resolve<SettingsView>();
        InGameSceneInfoView sceneInfoView = Object.FindObjectOfType<InGameSceneInfoView>();

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
}
