using UnityEditor;
using UnityEngine;
using UnityEngine.UI;
using TMPro;

public class SaveLoadPrefabBuilder : EditorWindow
{
    [MenuItem("Tools/Build SaveLoad Prefab")]
    public static void BuildPrefab()
    {
        string prefabPath = "Assets/Game/Prefabs/SaveLoadPopup.prefab";
        GameObject prefabAsset = AssetDatabase.LoadAssetAtPath<GameObject>(prefabPath);
        if (prefabAsset == null)
        {
            Debug.LogError("[SaveLoadPrefabBuilder] 프리팹 에셋을 찾을 수 없습니다.");
            return;
        }

        GameObject tempRoot = PrefabUtility.InstantiatePrefab(prefabAsset) as GameObject;
        if (tempRoot == null)
        {
            return;
        }

        Transform settingsPanel = tempRoot.transform.Find("SettingsPanel");
        if (settingsPanel != null)
        {
            int childCount = settingsPanel.childCount;
            for (int i = childCount - 1; i >= 0; i--)
            {
                DestroyImmediate(settingsPanel.GetChild(i).gameObject);
            }
        }
        else
        {
            GameObject newPanel = new GameObject("SettingsPanel", typeof(RectTransform), typeof(Image));
            newPanel.transform.SetParent(tempRoot.transform, false);
            settingsPanel = newPanel.transform;
        }

        GameObject leftArea = new GameObject("SlotListArea", typeof(RectTransform), typeof(Image), typeof(ScrollRect));
        leftArea.transform.SetParent(settingsPanel, false);
        RectTransform leftRt = leftArea.GetComponent<RectTransform>();
        leftRt.anchorMin = new Vector2(0, 0);
        leftRt.anchorMax = new Vector2(0.35f, 1);
        leftRt.sizeDelta = Vector2.zero;

        GameObject viewport = new GameObject("Viewport", typeof(RectTransform), typeof(Image), typeof(Mask));
        viewport.transform.SetParent(leftArea.transform, false);
        viewport.GetComponent<RectTransform>().anchorMin = Vector2.zero;
        viewport.GetComponent<RectTransform>().anchorMax = Vector2.one;
        viewport.GetComponent<RectTransform>().sizeDelta = Vector2.zero;

        GameObject content = new GameObject("Content", typeof(RectTransform), typeof(VerticalLayoutGroup));
        content.transform.SetParent(viewport.transform, false);
        RectTransform contentRt = content.GetComponent<RectTransform>();
        contentRt.anchorMin = new Vector2(0, 1);
        contentRt.anchorMax = new Vector2(1, 1);
        contentRt.sizeDelta = new Vector2(0, 500);

        ScrollRect scrollRect = leftArea.GetComponent<ScrollRect>();
        scrollRect.viewport = viewport.GetComponent<RectTransform>();
        scrollRect.content = contentRt;
        scrollRect.horizontal = false;
        scrollRect.vertical = true;

        GameObject rightArea = new GameObject("RightArea", typeof(RectTransform));
        rightArea.transform.SetParent(settingsPanel, false);
        RectTransform rightRt = rightArea.GetComponent<RectTransform>();
        rightRt.anchorMin = new Vector2(0.35f, 0);
        rightRt.anchorMax = new Vector2(1, 1);
        rightRt.sizeDelta = Vector2.zero;

        GameObject metaPanel = new GameObject("SlotMetaPanel", typeof(RectTransform), typeof(Image));
        metaPanel.transform.SetParent(rightArea.transform, false);
        RectTransform metaRt = metaPanel.GetComponent<RectTransform>();
        metaRt.anchorMin = new Vector2(0.05f, 0.55f);
        metaRt.anchorMax = new Vector2(0.95f, 0.95f);
        metaRt.sizeDelta = Vector2.zero;

        GameObject thumbnail = new GameObject("ThumbnailImage", typeof(RectTransform), typeof(Image));
        thumbnail.transform.SetParent(metaPanel.transform, false);
        RectTransform thumbRt = thumbnail.GetComponent<RectTransform>();
        thumbRt.anchorMin = new Vector2(0.02f, 0.05f);
        thumbRt.anchorMax = new Vector2(0.48f, 0.95f);
        thumbRt.sizeDelta = Vector2.zero;

        GameObject metaTextGo = new GameObject("SlotMetaText", typeof(RectTransform), typeof(TextMeshProUGUI));
        metaTextGo.transform.SetParent(metaPanel.transform, false);
        RectTransform metaTextRt = metaTextGo.GetComponent<RectTransform>();
        metaTextRt.anchorMin = new Vector2(0.52f, 0.5f);
        metaTextRt.anchorMax = new Vector2(0.98f, 0.95f);
        metaTextRt.sizeDelta = Vector2.zero;
        metaTextGo.GetComponent<TextMeshProUGUI>().fontSize = 20;

        GameObject detailTextGo = new GameObject("SlotDetailText", typeof(RectTransform), typeof(TextMeshProUGUI));
        detailTextGo.transform.SetParent(metaPanel.transform, false);
        RectTransform detailTextRt = detailTextGo.GetComponent<RectTransform>();
        detailTextRt.anchorMin = new Vector2(0.52f, 0.05f);
        detailTextRt.anchorMax = new Vector2(0.98f, 0.48f);
        detailTextRt.sizeDelta = Vector2.zero;
        detailTextGo.GetComponent<TextMeshProUGUI>().fontSize = 16;

        GameObject btnGroup = new GameObject("ActionButtonGroup", typeof(RectTransform), typeof(HorizontalLayoutGroup));
        btnGroup.transform.SetParent(rightArea.transform, false);
        RectTransform btnGroupRt = btnGroup.GetComponent<RectTransform>();
        btnGroupRt.anchorMin = new Vector2(0.05f, 0.4f);
        btnGroupRt.anchorMax = new Vector2(0.95f, 0.52f);
        btnGroupRt.sizeDelta = Vector2.zero;

        GameObject loadBtn = new GameObject("LoadButton", typeof(RectTransform), typeof(Image), typeof(Button));
        loadBtn.transform.SetParent(btnGroup.transform, false);
        loadBtn.GetComponent<Image>().color = new Color(0.75f, 0.22f, 0.17f, 1.0f);

        GameObject loadTxtGo = new GameObject("Text (TMP)", typeof(RectTransform), typeof(TextMeshProUGUI));
        loadTxtGo.transform.SetParent(loadBtn.transform, false);
        var loadTxt = loadTxtGo.GetComponent<TextMeshProUGUI>();
        loadTxt.text = "이어하기 (Load)";
        loadTxt.fontSize = 18;
        loadTxt.alignment = TextAlignmentOptions.Center;
        loadTxt.color = Color.white;
        loadTxtGo.GetComponent<RectTransform>().anchorMin = Vector2.zero;
        loadTxtGo.GetComponent<RectTransform>().anchorMax = Vector2.one;
        loadTxtGo.GetComponent<RectTransform>().sizeDelta = Vector2.zero;

        GameObject saveBtn = new GameObject("SaveButton", typeof(RectTransform), typeof(Image), typeof(Button));
        saveBtn.transform.SetParent(btnGroup.transform, false);

        GameObject saveTxtGo = new GameObject("Text (TMP)", typeof(RectTransform), typeof(TextMeshProUGUI));
        saveTxtGo.transform.SetParent(saveBtn.transform, false);
        var saveTxt = saveTxtGo.GetComponent<TextMeshProUGUI>();
        saveTxt.text = "덮어쓰기 (Save)";
        saveTxt.fontSize = 18;
        saveTxt.alignment = TextAlignmentOptions.Center;
        saveTxt.color = Color.black;
        saveTxtGo.GetComponent<RectTransform>().anchorMin = Vector2.zero;
        saveTxtGo.GetComponent<RectTransform>().anchorMax = Vector2.one;
        saveTxtGo.GetComponent<RectTransform>().sizeDelta = Vector2.zero;

        GameObject deleteBtn = new GameObject("DeleteButton", typeof(RectTransform), typeof(Image), typeof(Button));
        deleteBtn.transform.SetParent(btnGroup.transform, false);

        GameObject delTxtGo = new GameObject("Text (TMP)", typeof(RectTransform), typeof(TextMeshProUGUI));
        delTxtGo.transform.SetParent(deleteBtn.transform, false);
        var delTxt = delTxtGo.GetComponent<TextMeshProUGUI>();
        delTxt.text = "삭제 (새로 시작)";
        delTxt.fontSize = 18;
        delTxt.alignment = TextAlignmentOptions.Center;
        delTxt.color = Color.black;
        delTxtGo.GetComponent<RectTransform>().anchorMin = Vector2.zero;
        delTxtGo.GetComponent<RectTransform>().anchorMax = Vector2.one;
        delTxtGo.GetComponent<RectTransform>().sizeDelta = Vector2.zero;

        GameObject progressPanel = new GameObject("GlobalProgressPanel", typeof(RectTransform), typeof(Image));
        progressPanel.transform.SetParent(rightArea.transform, false);
        RectTransform progressRt = progressPanel.GetComponent<RectTransform>();
        progressRt.anchorMin = new Vector2(0.05f, 0.1f);
        progressRt.anchorMax = new Vector2(0.95f, 0.35f);
        progressRt.sizeDelta = Vector2.zero;

        GameObject progressTextGo = new GameObject("GlobalProgressText", typeof(RectTransform), typeof(TextMeshProUGUI));
        progressTextGo.transform.SetParent(progressPanel.transform, false);
        RectTransform progTextRt = progressTextGo.GetComponent<RectTransform>();
        progTextRt.anchorMin = Vector2.zero;
        progTextRt.anchorMax = Vector2.one;
        progTextRt.sizeDelta = Vector2.zero;
        progressTextGo.GetComponent<TextMeshProUGUI>().fontSize = 18;

        GameObject shortcutGo = new GameObject("ShortcutGuideText", typeof(RectTransform), typeof(TextMeshProUGUI));
        shortcutGo.transform.SetParent(settingsPanel.transform, false);
        RectTransform shortcutRt = shortcutGo.GetComponent<RectTransform>();
        shortcutRt.anchorMin = new Vector2(0.1f, 0.02f);
        shortcutRt.anchorMax = new Vector2(0.9f, 0.08f);
        shortcutRt.sizeDelta = Vector2.zero;
        shortcutGo.GetComponent<TextMeshProUGUI>().text = "Enter 로드 · Ctrl+S 저장 · Del 삭제 · Esc 뒤로";
        shortcutGo.GetComponent<TextMeshProUGUI>().alignment = TextAlignmentOptions.Center;

        SaveLoadView view = tempRoot.GetComponent<SaveLoadView>();
        if (view != null)
        {
            var serializedObj = new SerializedObject(view);
            serializedObj.FindProperty("m_contentContainer").objectReferenceValue = contentRt;
            serializedObj.FindProperty("m_thumbnailImage").objectReferenceValue = thumbnail.GetComponent<Image>();
            serializedObj.FindProperty("m_metaText").objectReferenceValue = metaTextGo.GetComponent<TextMeshProUGUI>();
            serializedObj.FindProperty("m_detailText").objectReferenceValue = detailTextGo.GetComponent<TextMeshProUGUI>();
            serializedObj.FindProperty("m_loadButton").objectReferenceValue = loadBtn.GetComponent<Button>();
            serializedObj.FindProperty("m_saveButton").objectReferenceValue = saveBtn.GetComponent<Button>();
            serializedObj.FindProperty("m_deleteButton").objectReferenceValue = deleteBtn.GetComponent<Button>();
            serializedObj.FindProperty("m_globalProgressText").objectReferenceValue = progressTextGo.GetComponent<TextMeshProUGUI>();
            serializedObj.ApplyModifiedProperties();
        }

        PrefabUtility.SaveAsPrefabAsset(tempRoot, prefabPath);
        DestroyImmediate(tempRoot);
        Debug.Log("[SaveLoadPrefabBuilder] 프리팹이 이미지 규격에 맞추어 완전 빌드 및 저장되었습니다.");
    }
}
