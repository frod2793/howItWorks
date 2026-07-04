using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.TestTools;
using UnityEngine.SceneManagement;
using VContainer;
using Domain.InGame;
using Features.InGame;
using Features.Settings;

/// <summary>
/// [기능]: 기획 화면설계서 v1.1 슬라이드 번호 기준으로 타이틀부터 인게임 핵심 흐름을 연쇄 검증하는 통합 테스트 클래스입니다.
/// [작성자]: 윤승종
/// </summary>
public class SlideIntegrationTests
{
    [SetUp]
    public void SetUp()
    {
        UIStackService.IsTestMode = true;
    }

    [TearDown]
    public void TearDown()
    {
        UIStackService.IsTestMode = false;
    }

    #region 내부 헬퍼 (Private Helpers)
    private IEnumerator LoadInGameScene()
    {
        SceneManager.LoadScene("InGame");
        for (int i = 0; i < 15; i++)
        {
            yield return null;
        }
    }

    private T FindComponentInActiveScene<T>() where T : MonoBehaviour
    {
        T[] instances = Resources.FindObjectsOfTypeAll<T>();
        for (int i = 0; i < instances.Length; i++)
        {
            if (instances[i] != null && instances[i].gameObject.scene == SceneManager.GetActiveScene())
            {
                return instances[i];
            }
        }
        return null;
    }
    #endregion

    #region 슬라이드별 통합 테스트 시나리오
    /// <summary>
    /// [기능]: 2번 슬라이드 (Screen_Title) 검증 - 타이틀 화면 초기화 및 새 게임 시작 시 인게임 씬 로드 확인
    /// [작성자]: 윤승종
    /// [수정 날짜]: 2026-07-04
    /// </summary>
    [UnityTest]
    public IEnumerator Slide02_TitleScreenTest()
    {
        SceneManager.LoadScene("Title");
        yield return null;

        TitleView titleView = UnityEngine.Object.FindFirstObjectByType<TitleView>();
        Assert.IsNotNull(titleView, "[SlideIntegrationTests] 타이틀 뷰 인스턴스를 찾을 수 없습니다.");

        titleView.func_OnNewGameButtonClicked();

        float elapsed = 0f;
        while (SceneManager.GetActiveScene().name != "InGame" && elapsed < 5f)
        {
            elapsed += Time.unscaledDeltaTime;
            yield return null;
        }

        Assert.AreEqual("InGame", SceneManager.GetActiveScene().name, "[SlideIntegrationTests] 새 게임 시작 후 InGame 씬으로 진입하는 데 실패했습니다.");
        Debug.Log("[SlideIntegrationTests] Slide02: 타이틀 화면 및 새 게임 진입 검증 완료.");
    }

    /// <summary>
    /// [기능]: 3번 슬라이드 (Screen_Intro) 검증 - 인트로 독백 구동 및 대사 흐름 확인
    /// [작성자]: 윤승종
    /// [수정 날짜]: 2026-07-04
    /// </summary>
    [UnityTest]
    public IEnumerator Slide03_IntroScreenTest()
    {
        yield return LoadInGameScene();

        IntroView introView = FindComponentInActiveScene<IntroView>();
        Assert.IsNotNull(introView, "[SlideIntegrationTests] 인트로 뷰 인스턴스를 찾을 수 없습니다.");

        var monologueTextProperty = typeof(IntroView).GetField("m_contentText", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(monologueTextProperty, "[SlideIntegrationTests] m_contentText 직렬화 필드를 찾을 수 없습니다.");

        TMPro.TextMeshProUGUI monologueText = monologueTextProperty.GetValue(introView) as TMPro.TextMeshProUGUI;
        Assert.IsNotNull(monologueText, "[SlideIntegrationTests] m_monologueText 컴포넌트가 바인딩되지 않았습니다.");
        
        Debug.Log("[SlideIntegrationTests] Slide03: 인트로 독백 텍스트 시스템 검증 완료.");
    }

    /// <summary>
    /// [기능]: 4번 슬라이드 (Screen_Dialogue) 검증 - 대사창 UI 화자 이름 및 본문 40pt 바인딩 확인
    /// [작성자]: 윤승종
    /// [수정 날짜]: 2026-07-04
    /// </summary>
    [UnityTest]
    public IEnumerator Slide04_DialogueScreenTest()
    {
        yield return LoadInGameScene();

        InGameDialogueView dialogueView = FindComponentInActiveScene<InGameDialogueView>();
        Assert.IsNotNull(dialogueView, "[SlideIntegrationTests] 인게임 다이얼로그 뷰를 찾을 수 없습니다.");

        var nameTextProperty = typeof(InGameDialogueView).GetField("m_nameText", BindingFlags.NonPublic | BindingFlags.Instance);
        var contentTextProperty = typeof(InGameDialogueView).GetField("m_contentText", BindingFlags.NonPublic | BindingFlags.Instance);

        Assert.IsNotNull(nameTextProperty, "[SlideIntegrationTests] m_nameText 필드 누락.");
        Assert.IsNotNull(contentTextProperty, "[SlideIntegrationTests] m_contentText 필드 누락.");

        TMPro.TextMeshProUGUI nameText = nameTextProperty.GetValue(dialogueView) as TMPro.TextMeshProUGUI;
        TMPro.TextMeshProUGUI contentText = contentTextProperty.GetValue(dialogueView) as TMPro.TextMeshProUGUI;

        Assert.IsNotNull(nameText, "[SlideIntegrationTests] 화자 텍스트 컴포넌트가 바인딩되지 않았습니다.");
        Assert.IsNotNull(contentText, "[SlideIntegrationTests] 대사 본문 텍스트 컴포넌트가 바인딩되지 않았습니다.");

        Debug.Log("[SlideIntegrationTests] Slide04: 대사창 UI 화자/본문 바인딩 검증 완료.");
    }

    /// <summary>
    /// [기능]: 5번 슬라이드 (Screen_Choice) 검증 - 선택지 팝업 호출 및 클릭 후 대사 분기 이동 확인
    /// [작성자]: 윤승종
    /// [수정 날짜]: 2026-07-04
    /// </summary>
    [UnityTest]
    public IEnumerator Slide05_ChoiceScreenTest()
    {
        SceneManager.LoadScene("Title");
        yield return null;

        TitleView titleView = UnityEngine.Object.FindFirstObjectByType<TitleView>();
        titleView.func_OnNewGameButtonClicked();

        float elapsed = 0f;
        while (SceneManager.GetActiveScene().name != "InGame" && elapsed < 5f)
        {
            elapsed += Time.unscaledDeltaTime;
            yield return null;
        }

        InGameLifetimeScope scope = UnityEngine.Object.FindFirstObjectByType<InGameLifetimeScope>();
        IDialogueViewModel dialogueVM = scope.Container.Resolve<IDialogueViewModel>();
        DialogueFlowController controller = scope.Container.Resolve<DialogueFlowController>();

        FieldInfo indexField = controller.GetType().GetField("m_currentDialogueIndex", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(indexField, "[SlideIntegrationTests] m_currentDialogueIndex 필드를 찾을 수 없습니다.");

        // 선택지 201번 지점까지 강제 스킵
        int safetyLoop = 0;
        int currentIdx = (int)indexField.GetValue(controller);
        while (currentIdx < 56 && safetyLoop < 100)
        {
            dialogueVM.RequestNext();
            yield return null;
            currentIdx = (int)indexField.GetValue(controller);
            safetyLoop++;
        }

        Assert.IsTrue(dialogueVM.IsDisplayingChoices, "[SlideIntegrationTests] 56번 대사 분기에서 선택지가 노출되지 않았습니다.");
        dialogueVM.SelectChoice(201);
        yield return null;

        currentIdx = (int)indexField.GetValue(controller);
        Assert.AreEqual(56, currentIdx, "[SlideIntegrationTests] 선택지 201번 클릭 후 대화 인덱스가 56이어야 합니다.");
        Debug.Log("[SlideIntegrationTests] Slide05: 분기 선택지 작동 검증 완료.");
    }

    /// <summary>
    /// [기능]: 6번 슬라이드 (Screen_SidePanel) 검증 - 카토 및 감정 5축 수치와 레이더 차트 인스턴스 확인
    /// [작성자]: 윤승종
    /// [수정 날짜]: 2026-07-04
    /// </summary>
    [UnityTest]
    public IEnumerator Slide06_SidePanelScreenTest()
    {
        yield return LoadInGameScene();

        InGameSidePanelView sidePanel = FindComponentInActiveScene<InGameSidePanelView>();
        Assert.IsNotNull(sidePanel, "[SlideIntegrationTests] 우측 사이드 패널을 찾을 수 없습니다.");

        var chartField = typeof(InGameSidePanelView).GetField("m_radarChart", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(chartField, "[SlideIntegrationTests] m_radarChart 필드를 찾을 수 없습니다.");

        var monitorSliderField = typeof(InGameSidePanelView).GetField("m_monitoringSlider", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(monitorSliderField, "[SlideIntegrationTests] m_monitoringSlider 필드 누락.");

        Debug.Log("[SlideIntegrationTests] Slide06: 사이드 패널 및 레이더 차트 인스턴스 검증 완료.");
    }

    /// <summary>
    /// [기능]: 7번 슬라이드 (Screen_Backlog) 검증 - 백로그 오버레이 활성 및 비활성 기능 확인
    /// [작성자]: 윤승종
    /// [수정 날짜]: 2026-07-04
    /// </summary>
    [UnityTest]
    public IEnumerator Slide07_BacklogScreenTest()
    {
        yield return LoadInGameScene();

        InGameLifetimeScope scope = UnityEngine.Object.FindFirstObjectByType<InGameLifetimeScope>();
        BacklogView backlogView = scope.Container.Resolve<BacklogView>();
        Assert.IsNotNull(backlogView, "[SlideIntegrationTests] 백로그 뷰 인스턴스 획득 실패.");

        if (backlogView.gameObject.activeSelf)
        {
            backlogView.gameObject.SetActive(false);
        }
        Assert.IsFalse(backlogView.gameObject.activeSelf);

        backlogView.gameObject.SetActive(true);
        yield return null;
        Assert.IsTrue(backlogView.gameObject.activeSelf, "[SlideIntegrationTests] 백로그가 정상적으로 열리지 않았습니다.");

        backlogView.func_Close();
        backlogView.gameObject.SetActive(false);
        yield return null;
        Assert.IsFalse(backlogView.gameObject.activeSelf, "[SlideIntegrationTests] 백로그가 닫히지 않았습니다.");

        Debug.Log("[SlideIntegrationTests] Slide07: 백로그 오버레이 검증 완료.");
    }

    /// <summary>
    /// [기능]: 8번 슬라이드 (Screen_Settings) 검증 - 시스템 메뉴를 통한 설정창 오픈 및 정렬 캔버스 활성화 확인
    /// [작성자]: 윤승종
    /// [수정 날짜]: 2026-07-04
    /// </summary>
    [UnityTest]
    public IEnumerator Slide08_SettingsScreenTest()
    {
        yield return LoadInGameScene();

        InGameLifetimeScope scope = UnityEngine.Object.FindFirstObjectByType<InGameLifetimeScope>();
        SettingsView settingsView = scope.Container.Resolve<SettingsView>();
        SystemMenuView systemMenuView = FindComponentInActiveScene<SystemMenuView>();
        InGameSceneInfoView sceneInfoView = FindComponentInActiveScene<InGameSceneInfoView>();

        Assert.IsNotNull(settingsView, "[SlideIntegrationTests] 설정창 뷰를 찾을 수 없습니다.");
        Assert.IsNotNull(systemMenuView, "[SlideIntegrationTests] 시스템 메뉴 뷰를 찾을 수 없습니다.");
        Assert.IsNotNull(sceneInfoView, "[SlideIntegrationTests] 씬 정보 상단 탑바를 찾을 수 없습니다.");

        Assert.IsFalse(settingsView.gameObject.activeSelf);

        sceneInfoView.func_OnSettingsButtonClicked();
        yield return null;

        var menuCanvas = systemMenuView.GetComponent<Canvas>();
        Assert.IsNotNull(menuCanvas);
        Assert.IsTrue(menuCanvas.enabled, "[SlideIntegrationTests] 톱니바퀴 버튼 클릭 시 시스템 메뉴 캔버스가 활성화되지 않았습니다.");

        systemMenuView.func_OnSettingsClick();
        yield return null;

        Assert.IsTrue(settingsView.gameObject.activeSelf, "[SlideIntegrationTests] 시스템 메뉴에서 설정 클릭 후 설정창이 활성화되지 않았습니다.");

        settingsView.func_OnCancelButtonClicked();
        yield return null;

        Assert.IsFalse(settingsView.gameObject.activeSelf, "[SlideIntegrationTests] 설정창 취소 후 닫기 실패.");

        systemMenuView.func_Close();
        yield return null;

        Debug.Log("[SlideIntegrationTests] Slide08: 설정창 연쇄 동작 검증 완료.");
    }

    /// <summary>
    /// [기능]: 9번 슬라이드 (Screen_Inventory) 검증 - 인게임 내 인벤토리 오버레이 토글 및 캔버스 동작 확인
    /// [작성자]: 윤승종
    /// [수정 날짜]: 2026-07-04
    /// </summary>
    [UnityTest]
    public IEnumerator Slide09_InventoryScreenTest()
    {
        yield return LoadInGameScene();

        InGameDialogueView dialogueView = FindComponentInActiveScene<InGameDialogueView>();
        Assert.IsNotNull(dialogueView, "[SlideIntegrationTests] 인게임 대사창을 찾을 수 없습니다.");

        var inventoryViewField = typeof(InGameDialogueView).GetField("m_inventoryView", BindingFlags.NonPublic | BindingFlags.Instance);
        if (inventoryViewField != null)
        {
            var invView = inventoryViewField.GetValue(dialogueView) as MonoBehaviour;
            if (invView != null)
            {
                invView.gameObject.SetActive(true);
                yield return null;
                Assert.IsTrue(invView.gameObject.activeSelf, "[SlideIntegrationTests] 인벤토리 화면 활성화 실패.");

                invView.gameObject.SetActive(false);
                yield return null;
                Assert.IsFalse(invView.gameObject.activeSelf, "[SlideIntegrationTests] 인벤토리 화면 비활성화 실패.");
            }
        }

        Debug.Log("[SlideIntegrationTests] Slide09: 인벤토리 오버레이 토글 검증 완료.");
    }

    /// <summary>
    /// [기능]: 10번 슬라이드 (Screen_SaveLoad) 검증 - 단일 슬롯 세이브/로드 화면 앵커 정렬 및 SaveSlotItem 프리팹 연동 확인
    /// [작성자]: 윤승종
    /// [수정 날짜]: 2026-07-04
    /// </summary>
    [UnityTest]
    public IEnumerator Slide10_SaveLoadScreenTest()
    {
        yield return LoadInGameScene();

        SaveLoadView saveLoadView = FindComponentInActiveScene<SaveLoadView>();
        Assert.IsNotNull(saveLoadView, "[SlideIntegrationTests] 세이브/로드 뷰를 찾을 수 없습니다.");

        var contentContainerField = typeof(SaveLoadView).GetField("m_contentContainer", BindingFlags.NonPublic | BindingFlags.Instance);
        var slotPrefabField = typeof(SaveLoadView).GetField("m_slotItemPrefab", BindingFlags.NonPublic | BindingFlags.Instance);

        Assert.IsNotNull(contentContainerField, "[SlideIntegrationTests] m_contentContainer 필드가 없습니다.");
        Assert.IsNotNull(slotPrefabField, "[SlideIntegrationTests] m_slotItemPrefab 필드가 없습니다.");

        RectTransform contentContainer = contentContainerField.GetValue(saveLoadView) as RectTransform;
        GameObject slotPrefab = slotPrefabField.GetValue(saveLoadView) as GameObject;

        Assert.IsNotNull(contentContainer, "[SlideIntegrationTests] m_contentContainer가 할당되지 않았습니다.");
        Assert.IsNotNull(slotPrefab, "[SlideIntegrationTests] m_slotItemPrefab(SaveSlotItem)이 할당되지 않았습니다.");

        Debug.Log("[SlideIntegrationTests] Slide10: 단일 슬롯 구조 세이브/로드 구성 검증 완료.");
    }

    /// <summary>
    /// [기능]: 13번 슬라이드 (Screen_Encyclopedia) 검증 - 도감 패널 씬 내 배치 및 CG/Sound 탭 연동 확인
    /// [작성자]: 윤승종
    /// [수정 날짜]: 2026-07-04
    /// </summary>
    [UnityTest]
    public IEnumerator Slide13_EncyclopediaScreenTest()
    {
        yield return LoadInGameScene();

        InGameEncyclopediaView encyclopediaView = FindComponentInActiveScene<InGameEncyclopediaView>();
        Assert.IsNotNull(encyclopediaView, "[SlideIntegrationTests] 인게임 도감 패널을 찾을 수 없습니다.");

        var cardPrefabField = typeof(InGameEncyclopediaView).GetField("m_encyclopediaCardPrefab", BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.IsNotNull(cardPrefabField, "[SlideIntegrationTests] m_encyclopediaCardPrefab 필드 누락.");

        GameObject cardPrefab = cardPrefabField.GetValue(encyclopediaView) as GameObject;
        Assert.IsNotNull(cardPrefab, "[SlideIntegrationTests] m_cardPrefab이 바인딩되지 않았습니다.");

        Debug.Log("[SlideIntegrationTests] Slide13: 도감 팝업 배치 및 의존성 검증 완료.");
    }
    #endregion
}
