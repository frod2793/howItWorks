using UnityEditor;
using UnityEngine;

#region 에디터 툴
/// <summary>
/// [설명]: PopupView 컴포넌트의 인스펙터 UI를 커스터마이징하여 테스트 버튼을 제공합니다.
/// </summary>
[CustomEditor(typeof(PopupView))]
public class PopupViewEditor : Editor
{
    public override void OnInspectorGUI()
    {
        base.OnInspectorGUI();

        PopupView view = (PopupView)target;

        EditorGUILayout.Space();
        GUI.backgroundColor = Color.cyan;
        
        if (GUILayout.Button("Test Popup (With Current Key)", GUILayout.Height(30)))
        {
            if (Application.isPlaying)
            {
                view.TestFromInspector();
            }
            else
            {
                Debug.LogWarning("[PopupViewEditor] 플레이 모드 전용 기능");
            }
        }
        
        GUI.backgroundColor = Color.white;
    }
}
#endregion
