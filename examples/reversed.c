/* rewritten to native from RE of mystery2 (radare2 pdc): secret = factorial loop */
#include <stdio.h>
int secret(int n){ int acc=1; for(int i=2;i<=n;i++) acc=acc*i; return acc; }
int main(void){ printf("mystery says: factorial(6) = %d\n", secret(6)); return 0; }
