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
using TMPro;

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
        Assert.AreEqual(59, currentIdx, "선택지 302번을 누른 뒤에는 대화 인덱스가 59이어야 합니다.");

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

    [UnityTest]
    public IEnumerator TestTitleScreenNavigation()
    {
        SceneManager.LoadScene("Title");
        yield return null;

        TitleLifetimeScope scope = Object.FindFirstObjectByType<TitleLifetimeScope>();
        Assert.IsNotNull(scope);

        TitleView titleView = Object.FindFirstObjectByType<TitleView>();
        Assert.IsNotNull(titleView);

        ITitleViewModel titleVM = scope.Container.Resolve<ITitleViewModel>();
        Assert.IsNotNull(titleVM);

        SettingsView settingsView = Object.FindFirstObjectByType<SettingsView>();
        Assert.IsNotNull(settingsView);
        if (settingsView.gameObject.activeSelf)
        {
            settingsView.gameObject.SetActive(false);
        }
        Assert.IsFalse(settingsView.gameObject.activeSelf);

        var progressTextField = typeof(TitleView).GetField("m_globalProgressText", BindingFlags.NonPublic | BindingFlags.Instance);
        if (progressTextField != null)
        {
            TMPro.TextMeshProUGUI progressText = progressTextField.GetValue(titleView) as TMPro.TextMeshProUGUI;
            if (progressText != null)
            {
                Assert.IsTrue(progressText.gameObject.activeSelf);
                Assert.IsTrue(progressText.text.Contains("회차") || progressText.text.Contains("엔딩"));
            }
        }

        var buttonsField = typeof(TitleView).GetField("m_menuButtons", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(buttonsField);
        Button[] buttons = buttonsField.GetValue(titleView) as Button[];
        Assert.IsNotNull(buttons);
        Assert.IsTrue(buttons.Length > 0);

        var focusIndexField = typeof(TitleView).GetField("m_currentFocusIndex", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(focusIndexField);

        int initialFocus = (int)focusIndexField.GetValue(titleView);
        int nextFocus = (initialFocus + 1) % buttons.Length;
        focusIndexField.SetValue(titleView, nextFocus);

        var updateVisualsMethod = typeof(TitleView).GetMethod("UpdateFocusVisuals", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(updateVisualsMethod);
        updateVisualsMethod.Invoke(titleView, new object[] { false });

        var highlightedText = buttons[nextFocus].GetComponentInChildren<TMPro.TMP_Text>();
        if (highlightedText != null)
        {
            Assert.AreEqual(new Color(0.75f, 0.22f, 0.17f, 1.0f), highlightedText.color);
        }

        Assert.IsFalse(settingsView.gameObject.activeSelf);

        var settingsBtnField = typeof(TitleView).GetField("m_settingsButton", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(settingsBtnField);
        Button settingsBtn = settingsBtnField.GetValue(titleView) as Button;
        Assert.IsNotNull(settingsBtn);

        settingsView.gameObject.SetActive(true);
        for (int i = 0; i < 20; i++)
        {
            yield return null;
        }

        Assert.IsTrue(settingsView.gameObject.activeSelf);

        settingsView.func_OnCancelButtonClicked();
        settingsView.gameObject.SetActive(false);
        yield return null;

        Assert.IsFalse(settingsView.gameObject.activeSelf);
        Assert.IsTrue(titleView.gameObject.activeSelf);
    }

    private IEnumerator LoadInGameScene()
    {
        SceneManager.LoadScene("InGame");
        for (int i = 0; i < 10; i++)
        {
            yield return null;
        }
    }

    [UnityTest]
    public IEnumerator TestInGame_01_SceneTitle()
    {
        yield return LoadInGameScene();
        InGameSceneInfoView view = Object.FindFirstObjectByType<InGameSceneInfoView>();
        var titleTextProperty = typeof(InGameSceneInfoView).GetField("m_sceneTitleText", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(titleTextProperty);
        TMPro.TextMeshProUGUI titleText = titleTextProperty.GetValue(view) as TMPro.TextMeshProUGUI;
        Assert.IsNotNull(titleText);
    }

    [UnityTest]
    public IEnumerator TestInGame_02_Playthrough()
    {
        yield return LoadInGameScene();
        InGameSceneInfoView view = Object.FindFirstObjectByType<InGameSceneInfoView>();
        var playthroughTextProperty = typeof(InGameSceneInfoView).GetField("m_playthroughText", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(playthroughTextProperty);
        TMPro.TextMeshProUGUI playthroughText = playthroughTextProperty.GetValue(view) as TMPro.TextMeshProUGUI;
        Assert.IsNotNull(playthroughText);
    }

    [UnityTest]
    public IEnumerator TestInGame_03_SettingsOverlay()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SettingsView settingsView = scope.Container.Resolve<SettingsView>();
        Assert.IsNotNull(settingsView);

        if (settingsView.gameObject.activeSelf)
        {
            settingsView.gameObject.SetActive(false);
        }
        Assert.IsFalse(settingsView.gameObject.activeSelf);
        settingsView.gameObject.SetActive(true);
        for (int i = 0; i < 20; i++)
        {
            yield return null;
        }
        Assert.IsTrue(settingsView.gameObject.activeSelf);
        settingsView.func_OnCancelButtonClicked();
        settingsView.gameObject.SetActive(false);
        yield return null;
        Assert.IsFalse(settingsView.gameObject.activeSelf);
    }

    [UnityTest]
    public IEnumerator TestInGame_04_CatoStockChoiceLock()
    {
        var cardGo = new GameObject("OptionCardTemp", typeof(RectTransform), typeof(CanvasGroup), typeof(Button), typeof(Image));
        var cardView = cardGo.AddComponent<InGameDialogueOptionCardView>();
        var cardTitle = new GameObject("Title").AddComponent<TMPro.TextMeshProUGUI>();
        var cardDesc = new GameObject("Desc").AddComponent<TMPro.TextMeshProUGUI>();
        cardTitle.transform.SetParent(cardGo.transform, false);
        cardDesc.transform.SetParent(cardGo.transform, false);
        
        typeof(InGameDialogueOptionCardView).GetField("m_titleText", BindingFlags.NonPublic | BindingFlags.Instance).SetValue(cardView, cardTitle);
        typeof(InGameDialogueOptionCardView).GetField("m_descriptionText", BindingFlags.NonPublic | BindingFlags.Instance).SetValue(cardView, cardDesc);
        
        var mockChoice = new DialogueChoiceDTO();
        mockChoice.ChoiceId = 999;
        mockChoice.Title = "카토 선택지";
        mockChoice.IsLocked = true;
        
        cardView.SetCardData(mockChoice, (id) => {});
        Assert.IsFalse(cardGo.GetComponent<Button>().interactable);
        Assert.AreEqual(0.5f, cardGo.GetComponent<CanvasGroup>().alpha);
        Object.DestroyImmediate(cardGo);
        yield return null;
    }

    [UnityTest]
    public IEnumerator TestInGame_05_RadarEmotionRendering()
    {
        yield return LoadInGameScene();
        InGameSidePanelView sidePanel = Object.FindFirstObjectByType<InGameSidePanelView>();
        Assert.IsNotNull(sidePanel);
        
        var updateMethod = typeof(InGameSidePanelView).GetMethod("UpdateSidePanelData", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(updateMethod);

        var testData = new SidePanelDTO();
        testData.CatoStocks = 2;
        testData.MaxCatoStocks = 5;
        testData.Sadness = 3;
        testData.Joy = 3;
        testData.Curiosity = 8;
        testData.Fear = 1;
        testData.Confusion = 1;
        
        updateMethod.Invoke(sidePanel, new object[] { testData });
        
        var sadnessTextVal = typeof(InGameSidePanelView).GetField("m_sadnessText", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(sidePanel) as TMPro.TextMeshProUGUI;
        Assert.IsNotNull(sadnessTextVal);
        Assert.IsTrue(sadnessTextVal.text.Contains("슬픔") && sadnessTextVal.text.Contains("3"));
    }

    [UnityTest]
    public IEnumerator TestInGame_06_DominantEmotionAndYearning()
    {
        yield return LoadInGameScene();
        InGameSidePanelView sidePanel = Object.FindFirstObjectByType<InGameSidePanelView>();
        var updateMethod = typeof(InGameSidePanelView).GetMethod("UpdateSidePanelData", BindingFlags.NonPublic | BindingFlags.Instance);

        var testData = new SidePanelDTO();
        testData.Sadness = 3;
        testData.Joy = 3;
        testData.Curiosity = 8;
        testData.Fear = 1;
        testData.Confusion = 1;

        updateMethod.Invoke(sidePanel, new object[] { testData });

        var dominantTextVal = typeof(InGameSidePanelView).GetField("m_dominantEmotionText", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(sidePanel) as TMPro.TextMeshProUGUI;
        Assert.IsNotNull(dominantTextVal);
        Assert.IsTrue(dominantTextVal.text.Contains("호기심") && dominantTextVal.text.Contains("8"));

        var yearningTextVal = typeof(InGameSidePanelView).GetField("m_yearningStatusText", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(sidePanel) as TMPro.TextMeshProUGUI;
        Assert.IsNotNull(yearningTextVal);
        Assert.IsTrue(yearningTextVal.text.Contains("활성"));

        testData.Sadness = 2;
        updateMethod.Invoke(sidePanel, new object[] { testData });
        Assert.IsTrue(yearningTextVal.text.Contains("비활성"));
    }

    [UnityTest]
    public IEnumerator TestInGame_07_MonitoringSlider()
    {
        yield return LoadInGameScene();
        InGameSidePanelView sidePanel = Object.FindFirstObjectByType<InGameSidePanelView>();
        var updateMethod = typeof(InGameSidePanelView).GetMethod("UpdateSidePanelData", BindingFlags.NonPublic | BindingFlags.Instance);

        var testData = new SidePanelDTO();
        testData.Monitoring = 5;

        updateMethod.Invoke(sidePanel, new object[] { testData });

        var monitorSliderVal = typeof(InGameSidePanelView).GetField("m_monitoringSlider", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(sidePanel) as Slider;
        Assert.IsNotNull(monitorSliderVal);
        Assert.IsTrue(Mathf.Approximately(0.5f, monitorSliderVal.value));
    }

    [UnityTest]
    public IEnumerator TestInGame_08_TrustSlider()
    {
        yield return LoadInGameScene();
        InGameSidePanelView sidePanel = Object.FindFirstObjectByType<InGameSidePanelView>();
        var updateMethod = typeof(InGameSidePanelView).GetMethod("UpdateSidePanelData", BindingFlags.NonPublic | BindingFlags.Instance);

        var testData = new SidePanelDTO();
        testData.Trust = 4;

        updateMethod.Invoke(sidePanel, new object[] { testData });

        var trustSliderVal = typeof(InGameSidePanelView).GetField("m_trustSlider", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(sidePanel) as Slider;
        Assert.IsNotNull(trustSliderVal);
        Assert.IsTrue(Mathf.Approximately(0.4f, trustSliderVal.value));
    }

    [UnityTest]
    public IEnumerator TestInGame_09_LoopAwarenessBlocks()
    {
        yield return LoadInGameScene();
        InGameSidePanelView sidePanel = Object.FindFirstObjectByType<InGameSidePanelView>();
        var updateMethod = typeof(InGameSidePanelView).GetMethod("UpdateSidePanelData", BindingFlags.NonPublic | BindingFlags.Instance);

        var testData = new SidePanelDTO();
        testData.LoopAwareness = 3;
        testData.MaxLoopAwareness = 5;

        updateMethod.Invoke(sidePanel, new object[] { testData });

        var loopBlocksVal = typeof(InGameSidePanelView).GetField("m_loopBlocks", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(sidePanel) as GameObject[];
        Assert.IsNotNull(loopBlocksVal);
        int activeLoops = 0;
        for (int i = 0; i < loopBlocksVal.Length; i++)
        {
            if (loopBlocksVal[i] != null && loopBlocksVal[i].activeSelf)
            {
                activeLoops++;
            }
        }
        Assert.AreEqual(3, activeLoops);
    }

    [UnityTest]
    public IEnumerator TestInGame_10_CharacterIllustView()
    {
        yield return LoadInGameScene();
        InGameCharacterView characterView = Object.FindFirstObjectByType<InGameCharacterView>();
        Assert.IsNotNull(characterView);
    }

    [UnityTest]
    public IEnumerator TestInGame_11_SpeakerNameText()
    {
        yield return LoadInGameScene();
        InGameDialogueView dialogueView = Object.FindFirstObjectByType<InGameDialogueView>();
        var speakerNameField = typeof(InGameDialogueView).GetField("m_nameText", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(speakerNameField);
        TMPro.TextMeshProUGUI speakerText = speakerNameField.GetValue(dialogueView) as TMPro.TextMeshProUGUI;
        Assert.IsNotNull(speakerText);
    }

    [UnityTest]
    public IEnumerator TestInGame_12_DialogueContent40pt()
    {
        yield return LoadInGameScene();
        InGameDialogueView dialogueView = Object.FindFirstObjectByType<InGameDialogueView>();
        var contentTextField = typeof(InGameDialogueView).GetField("m_contentText", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(contentTextField);
        TMPro.TextMeshProUGUI contentText = contentTextField.GetValue(dialogueView) as TMPro.TextMeshProUGUI;
        Assert.IsNotNull(contentText);
    }

    [UnityTest]
    public IEnumerator TestInGame_13_LineCounterFormat()
    {
        yield return LoadInGameScene();
        InGameDialogueView dialogueView = Object.FindFirstObjectByType<InGameDialogueView>();
        var lineProgressField = typeof(InGameDialogueView).GetField("m_lineProgressText", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(lineProgressField);
        TMPro.TextMeshProUGUI progressText = lineProgressField.GetValue(dialogueView) as TMPro.TextMeshProUGUI;
        Assert.IsNotNull(progressText);
        
        var mockDialogue = new DialogueDTO();
        mockDialogue.CurrentLine = 12;
        mockDialogue.TotalLines = 48;
        mockDialogue.SpeakerName = "테스터";
        mockDialogue.Content = "테스트 대사";
        
        var updateDialogueMethod = typeof(InGameDialogueView).GetMethod("UpdateDialogue", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(updateDialogueMethod);
        updateDialogueMethod.Invoke(dialogueView, new object[] { mockDialogue });
        Assert.AreEqual("12 / 48", progressText.text);
    }

    [UnityTest]
    public IEnumerator TestInGame_14_BacklogOverlay()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        BacklogView backlogView = scope.Container.Resolve<BacklogView>();
        Assert.IsNotNull(backlogView);

        Assert.IsFalse(backlogView.gameObject.activeSelf);
        backlogView.gameObject.SetActive(true);
        for (int i = 0; i < 20; i++)
        {
            yield return null;
        }
        Assert.IsTrue(backlogView.gameObject.activeSelf);
        backlogView.func_Close();
        backlogView.gameObject.SetActive(false);
        yield return null;
        Assert.IsFalse(backlogView.gameObject.activeSelf);
    }

    [UnityTest]
    public IEnumerator TestInGame_15_InventoryOverlayAndSystem()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        InGameDialogueView dialogueView = Object.FindFirstObjectByType<InGameDialogueView>();
        
        var inventoryViewField = typeof(InGameDialogueView).GetField("m_inventoryView", BindingFlags.NonPublic | BindingFlags.Instance);
        if (inventoryViewField != null)
        {
            var invView = inventoryViewField.GetValue(dialogueView) as MonoBehaviour;
            if (invView != null)
            {
                if (invView.gameObject.activeSelf)
                {
                    invView.gameObject.SetActive(false);
                }
                Assert.IsFalse(invView.gameObject.activeSelf);
                invView.gameObject.SetActive(true);
                for (int i = 0; i < 20; i++)
                {
                    yield return null;
                }
                Assert.IsTrue(invView.gameObject.activeSelf);
                invView.gameObject.SetActive(false);
            }
        }
        
        var katoInventory = scope.Container.Resolve<InGameInventorySystem>();
        Assert.IsNotNull(katoInventory);
    }

    [UnityTest]
    public IEnumerator TestSettings_01_CategoryTabs()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SettingsView settingsView = scope.Container.Resolve<SettingsView>();
        Assert.IsNotNull(settingsView);

        var audioPanel = typeof(SettingsView).GetField("m_audioPanel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as GameObject;
        var textPanel = typeof(SettingsView).GetField("m_textPanel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as GameObject;
        var displayPanel = typeof(SettingsView).GetField("m_displayPanel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as GameObject;
        var accessibilityPanel = typeof(SettingsView).GetField("m_accessibilityPanel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as GameObject;
        var savePanel = typeof(SettingsView).GetField("m_savePanel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as GameObject;
        var inputPanel = typeof(SettingsView).GetField("m_inputPanel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as GameObject;

        settingsView.func_OnAudioTabButtonClicked();
        Assert.IsTrue(audioPanel.activeSelf);
        Assert.IsFalse(textPanel.activeSelf);

        settingsView.func_OnTextTabButtonClicked();
        Assert.IsTrue(textPanel.activeSelf);
        Assert.IsFalse(audioPanel.activeSelf);

        settingsView.func_OnDisplayTabButtonClicked();
        Assert.IsTrue(displayPanel.activeSelf);

        settingsView.func_OnAccessibilityTabButtonClicked();
        Assert.IsTrue(accessibilityPanel.activeSelf);

        settingsView.func_OnSaveTabButtonClicked();
        Assert.IsTrue(savePanel.activeSelf);

        settingsView.func_OnInputTabButtonClicked();
        Assert.IsTrue(inputPanel.activeSelf);
    }

    [UnityTest]
    public IEnumerator TestSettings_02_CategoryTitleDescription()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SettingsView settingsView = scope.Container.Resolve<SettingsView>();
        Assert.IsNotNull(settingsView);

        var categoryTitle = Object.FindObjectsByType<TMP_Text>(FindObjectsSortMode.None);
        Assert.IsNotNull(categoryTitle);
    }

    [UnityTest]
    public IEnumerator TestSettings_03_Sliders()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SettingsView settingsView = scope.Container.Resolve<SettingsView>();
        var viewModel = typeof(SettingsView).GetField("m_viewModel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as ISettingsViewModel;
        Assert.IsNotNull(viewModel);

        var masterSlider = typeof(SettingsView).GetField("m_masterVolumeSlider", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as Slider;
        Assert.IsNotNull(masterSlider);

        masterSlider.onValueChanged.Invoke(50f);
        Assert.IsTrue(Mathf.Approximately(0.5f, viewModel.MasterVolume));

        var bgmSlider = typeof(SettingsView).GetField("m_bgmVolumeSlider", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as Slider;
        if (bgmSlider != null)
        {
            bgmSlider.onValueChanged.Invoke(70f);
            Assert.IsTrue(Mathf.Approximately(0.7f, viewModel.BGMVolume));
        }
    }

    [UnityTest]
    public IEnumerator TestSettings_04_Toggles()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SettingsView settingsView = scope.Container.Resolve<SettingsView>();
        var viewModel = typeof(SettingsView).GetField("m_viewModel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as ISettingsViewModel;
        Assert.IsNotNull(viewModel);

        var toggle = typeof(SettingsView).GetField("m_muteOnFocusLostToggle", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as Toggle;
        Assert.IsNotNull(toggle);

        toggle.onValueChanged.Invoke(false);
        Assert.IsFalse(viewModel.MuteOnFocusLost);

        toggle.onValueChanged.Invoke(true);
        Assert.IsTrue(viewModel.MuteOnFocusLost);
    }

    [UnityTest]
    public IEnumerator TestSettings_05_Dropdowns()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SettingsView settingsView = scope.Container.Resolve<SettingsView>();
        Assert.IsNotNull(settingsView);

        var dropdown = typeof(SettingsView).GetField("m_outputDeviceDropdown", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as TMP_Dropdown;
        Assert.IsNotNull(dropdown);
    }

    [UnityTest]
    public IEnumerator TestSettings_06_RestoreDefault()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SettingsView settingsView = scope.Container.Resolve<SettingsView>();
        var viewModel = typeof(SettingsView).GetField("m_viewModel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as ISettingsViewModel;
        Assert.IsNotNull(viewModel);

        viewModel.MasterVolume = 0.2f;
        viewModel.MuteOnFocusLost = false;

        settingsView.func_OnRestoreDefaultButtonClicked();
        Assert.IsTrue(Mathf.Approximately(0.8f, viewModel.MasterVolume));
        Assert.IsTrue(viewModel.MuteOnFocusLost);
    }

    [UnityTest]
    public IEnumerator TestSettings_07_Cancel()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SettingsView settingsView = scope.Container.Resolve<SettingsView>();
        var viewModel = typeof(SettingsView).GetField("m_viewModel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as ISettingsViewModel;
        Assert.IsNotNull(viewModel);

        if (settingsView.gameObject.activeSelf == false)
        {
            settingsView.gameObject.SetActive(true);
        }

        viewModel.MasterVolume = 0.1f;
        settingsView.func_OnCancelButtonClicked();
        settingsView.gameObject.SetActive(false);
        yield return null;

        Assert.IsFalse(settingsView.gameObject.activeSelf);
    }

    [UnityTest]
    public IEnumerator TestSettings_08_Apply()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SettingsView settingsView = scope.Container.Resolve<SettingsView>();
        var viewModel = typeof(SettingsView).GetField("m_viewModel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(settingsView) as ISettingsViewModel;
        Assert.IsNotNull(viewModel);

        if (settingsView.gameObject.activeSelf == false)
        {
            settingsView.gameObject.SetActive(true);
        }

        viewModel.MasterVolume = 0.9f;
        settingsView.func_OnApplyButtonClicked();
        settingsView.gameObject.SetActive(false);
        yield return null;

        Assert.IsFalse(settingsView.gameObject.activeSelf);
    }

    [UnityTest]
    public IEnumerator TestSaveLoad_01_Thumbnail()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SaveLoadView saveLoadView = scope.Container.Resolve<SaveLoadView>();
        Assert.IsNotNull(saveLoadView);

        saveLoadView.func_Open(true);
        yield return null;

        var thumbnailImg = typeof(SaveLoadView).GetField("m_thumbnailImage", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(saveLoadView) as Image;
        Assert.IsNotNull(thumbnailImg);
        
        saveLoadView.func_Close();
    }

    [UnityTest]
    public IEnumerator TestSaveLoad_02_Metadata()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SaveLoadView saveLoadView = scope.Container.Resolve<SaveLoadView>();
        var viewModel = typeof(SaveLoadView).GetField("m_viewModel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(saveLoadView) as ISaveLoadViewModel;
        Assert.IsNotNull(viewModel);

        saveLoadView.func_Open(true);
        yield return null;

        viewModel.SelectSlot(0);
        var metaText = typeof(SaveLoadView).GetField("m_metaText", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(saveLoadView) as TextMeshProUGUI;
        Assert.IsNotNull(metaText);
        
        saveLoadView.func_Close();
    }

    [UnityTest]
    public IEnumerator TestSaveLoad_03_DetailText()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SaveLoadView saveLoadView = scope.Container.Resolve<SaveLoadView>();
        var viewModel = typeof(SaveLoadView).GetField("m_viewModel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(saveLoadView) as ISaveLoadViewModel;
        Assert.IsNotNull(viewModel);

        saveLoadView.func_Open(true);
        yield return null;

        viewModel.SelectSlot(0);
        var detailText = typeof(SaveLoadView).GetField("m_detailText", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(saveLoadView) as TextMeshProUGUI;
        Assert.IsNotNull(detailText);

        saveLoadView.func_Close();
    }

    [UnityTest]
    public IEnumerator TestSaveLoad_04_LoadAction()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SaveLoadView saveLoadView = scope.Container.Resolve<SaveLoadView>();
        var viewModel = typeof(SaveLoadView).GetField("m_viewModel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(saveLoadView) as ISaveLoadViewModel;
        Assert.IsNotNull(viewModel);

        saveLoadView.func_Open(true);
        yield return null;

        viewModel.SelectSlot(0);
        saveLoadView.func_OnLoadButtonClick();
        yield return null;

        saveLoadView.func_Close();
    }

    [UnityTest]
    public IEnumerator TestSaveLoad_05_SaveAction()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SaveLoadView saveLoadView = scope.Container.Resolve<SaveLoadView>();
        var viewModel = typeof(SaveLoadView).GetField("m_viewModel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(saveLoadView) as ISaveLoadViewModel;
        Assert.IsNotNull(viewModel);

        saveLoadView.func_Open(true);
        yield return null;

        viewModel.SelectSlot(0);
        
        string saveDir = System.IO.Path.Combine(Application.persistentDataPath, "Saves");
        if (System.IO.Directory.Exists(saveDir) == false)
        {
            System.IO.Directory.CreateDirectory(saveDir);
        }
        string pngPath = System.IO.Path.Combine(saveDir, "save_slot_0.png");
        if (System.IO.File.Exists(pngPath))
        {
            System.IO.File.Delete(pngPath);
        }

        saveLoadView.func_OnSaveButtonClick();
        for (int i = 0; i < 15; i++)
        {
            yield return null;
        }

        Assert.IsTrue(System.IO.File.Exists(pngPath), "[IntegrationTest] 세이브 시 스크린샷 png 썸네일이 생성되어야 합니다.");
        
        saveLoadView.func_Close();
    }

    [UnityTest]
    public IEnumerator TestSaveLoad_06_DeleteAction()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SaveLoadView saveLoadView = scope.Container.Resolve<SaveLoadView>();
        var viewModel = typeof(SaveLoadView).GetField("m_viewModel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(saveLoadView) as ISaveLoadViewModel;
        Assert.IsNotNull(viewModel);

        saveLoadView.func_Open(true);
        yield return null;

        viewModel.SelectSlot(0);
        
        string saveDir = System.IO.Path.Combine(Application.persistentDataPath, "Saves");
        string pngPath = System.IO.Path.Combine(saveDir, "save_slot_0.png");
        if (System.IO.File.Exists(pngPath) == false)
        {
            System.IO.File.WriteAllBytes(pngPath, new byte[] { 0, 1, 2 });
        }

        saveLoadView.func_OnDeleteButtonClick();
        yield return null;

        Assert.IsFalse(System.IO.File.Exists(pngPath), "[IntegrationTest] 슬롯 삭제 시 스크린샷 png 썸네일 파일도 함께 제거되어야 합니다.");
        
        saveLoadView.func_Close();
    }

    [UnityTest]
    public IEnumerator TestSaveLoad_07_GlobalProgress()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SaveLoadView saveLoadView = scope.Container.Resolve<SaveLoadView>();
        var viewModel = typeof(SaveLoadView).GetField("m_viewModel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(saveLoadView) as ISaveLoadViewModel;
        Assert.IsNotNull(viewModel);

        saveLoadView.func_Open(true);
        yield return null;

        var progressText = typeof(SaveLoadView).GetField("m_globalProgressText", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(saveLoadView) as TextMeshProUGUI;
        Assert.IsNotNull(progressText);
        Assert.IsTrue(progressText.text.Contains("엔딩") && progressText.text.Contains("도전과제"), "[IntegrationTest] 글로벌 진행도 텍스트가 올바른 포맷이어야 합니다.");

        saveLoadView.func_Close();
    }

    [UnityTest]
    public IEnumerator TestSaveLoad_08_KeyboardNavigation()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        SaveLoadView saveLoadView = scope.Container.Resolve<SaveLoadView>();
        var viewModel = typeof(SaveLoadView).GetField("m_viewModel", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(saveLoadView) as ISaveLoadViewModel;
        Assert.IsNotNull(viewModel);

        saveLoadView.func_Open(true);
        yield return null;

        viewModel.SelectSlot(0);
        viewModel.SelectSlot(1);
        Assert.AreEqual(1, viewModel.SelectedSlotIndex, "[IntegrationTest] 슬롯 포커스 이동 변경 정합성 검증 실패");

        saveLoadView.func_Close();
        yield return null;
        Assert.IsFalse(saveLoadView.gameObject.activeSelf);
    }

    [UnityTest]
    public IEnumerator TestInGame_16_AutoplayWorkflow()
    {
        yield return LoadInGameScene();
        InGameLifetimeScope scope = Object.FindFirstObjectByType<InGameLifetimeScope>();
        Assert.IsNotNull(scope);
        Assert.IsNotNull(scope.Container);

        IDialogueViewModel dialogueVM = scope.Container.Resolve<IDialogueViewModel>();
        Assert.IsNotNull(dialogueVM);

        InGameSidePanelView sidePanelView = Object.FindFirstObjectByType<InGameSidePanelView>();
        Assert.IsNotNull(sidePanelView);

        sidePanelView.func_OnAutoButtonClicked();
        yield return null;

        Assert.IsTrue(dialogueVM.IsAutoPlayActive, "[IntegrationTest] 뷰 버튼 클릭 시 뷰모델의 IsAutoPlayActive가 활성화되어야 합니다.");

        DialogueFlowController controller = scope.Container.Resolve<DialogueFlowController>();
        FieldInfo field = controller.GetType().GetField("m_currentDialogueIndex", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(field);

        int initialIdx = (int)field.GetValue(controller);

        float elapsed = 0f;
        while (elapsed < 5f)
        {
            elapsed += Time.unscaledDeltaTime;
            yield return null;
        }

        int nextIdx = (int)field.GetValue(controller);
        Assert.Greater(nextIdx, initialIdx, "[IntegrationTest] 오토플레이 활성화 시 시간 경과 후 대사가 자동으로 진행되어야 합니다.");

        sidePanelView.func_OnAutoButtonClicked();
        yield return null;
        Assert.IsFalse(dialogueVM.IsAutoPlayActive, "[IntegrationTest] 뷰 버튼 재클릭 시 뷰모델의 IsAutoPlayActive가 비활성화되어야 합니다.");
    }
}